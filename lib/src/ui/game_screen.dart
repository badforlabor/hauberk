import 'dart:math' as math;

import 'package:malison/malison.dart';
import 'package:malison/malison_web.dart';
import 'package:piecemeal/piecemeal.dart';

// TODO: Directly importing this is a little hacky. Put "appearance" on Element?
import '../content/elements.dart';
import '../engine.dart';
import '../hues.dart';
import 'close_door_dialog.dart';
import 'direction_dialog.dart';
import 'draw.dart';
import 'effect.dart';
import 'forfeit_dialog.dart';
import 'game_over_screen.dart';
import 'hero_info_dialog.dart';
import 'input.dart';
import 'item_dialog.dart';
import 'select_skill_dialog.dart';
import 'skill_dialog.dart';
import 'target_dialog.dart';
import 'wizard_dialog.dart';

class GameScreen extends Screen<Input> {
  final Game game;

  final HeroSave _save;
  List<Effect> _effects = <Effect>[];

  /// The number of ticks left to wait before restarting the game loop after
  /// coming back from a dialog where the player chose an action for the hero.
  int _pause = 0;

  /// The size of the [Stage] view area.
  final viewSize = new Vec(60, 34);

  /// The portion of the [Stage] currently in view on screen.
  Rect _cameraBounds;
  Rect get cameraBounds => _cameraBounds;

  Actor _targetActor;
  Vec _target;

  UsableSkill _lastSkill;

  void targetActor(Actor value) {
    if (_targetActor != value) dirty();

    _targetActor = value;
    _target = null;
  }

  /// Targets the floor at [pos].
  void targetFloor(Vec pos) {
    if (_targetActor != null || _target != pos) dirty();

    _targetActor = null;
    _target = pos;
  }

  /// Gets the currently targeted position.
  ///
  /// If targeting an actor, gets the actor's position.
  Vec get currentTarget {
    // If we're targeting an actor, use its position.
    if (currentTargetActor != null) return currentTargetActor.pos;

    // Forget the targeted floor if we know the hero can't see it.
    if (_target != null) {
      var tile = game.stage[_target];

      // TODO: Should use isVisible? Can you still target a reachable tile in
      // the dark?
      if (tile.isExplored && (tile.isOccluded || tile.blocksView)) {
        _target = null;
      }
    }

    return _target;
  }

  /// The currently targeted actor, if any.
  Actor get currentTargetActor {
    // Forget the target if it dies or goes offscreen.
    if (_targetActor != null) {
      if (!_targetActor.isAlive || !_targetActor.isVisibleToHero) {
        _targetActor = null;
      }
    }

    if (_targetActor != null) return _targetActor;

    // If we're targeting the floor, see if there is an actor there.
    if (_target != null) {
      return game.stage.actorAt(_target);
    }

    return null;
  }

  GameScreen(this._save, this.game) {
    _positionCamera();
  }

  bool handleInput(Input input) {
    var action;

    switch (input) {
      case Input.quit:
        // TODO: Should confirm first.
        if (game.stage[game.hero.pos].isExit) {
          _save.copyFrom(game.hero);

          // Remember that this depth was reached.
          _save.maxDepth = math.max(_save.maxDepth, game.depth);
          ui.pop(true);
        } else {
          game.log.error('You cannot exit from here.');
          dirty();
        }
        break;

      case Input.forfeit:
        ui.push(new ForfeitDialog(game));
        break;
      case Input.selectSkill:
        ui.push(new SelectSkillDialog(game));
        break;
      case Input.editSkills:
        ui.push(new SkillDialog(game.content, game.hero));
        break;
      case Input.heroInfo:
        ui.push(new HeroInfoDialog(game.hero));
        break;
      case Input.drop:
        ui.push(new ItemDialog.drop(this));
        break;
      case Input.use:
        ui.push(new ItemDialog.use(this));
        break;
      case Input.toss:
        ui.push(new ItemDialog.toss(this));
        break;

      case Input.rest:
        if (!game.hero.rest()) {
          // Show the message.
          dirty();
        }
        break;

      case Input.closeDoor:
        closeDoor();
        break;
      case Input.pickUp:
        pickUp();
        break;
      case Input.unequip:
        ui.push(new ItemDialog.unequip(this));
        break;

      case Input.nw:
        action = new WalkAction(Direction.nw);
        break;
      case Input.n:
        action = new WalkAction(Direction.n);
        break;
      case Input.ne:
        action = new WalkAction(Direction.ne);
        break;
      case Input.w:
        action = new WalkAction(Direction.w);
        break;
      case Input.ok:
        action = new WalkAction(Direction.none);
        break;
      case Input.e:
        action = new WalkAction(Direction.e);
        break;
      case Input.sw:
        action = new WalkAction(Direction.sw);
        break;
      case Input.s:
        action = new WalkAction(Direction.s);
        break;
      case Input.se:
        action = new WalkAction(Direction.se);
        break;

      case Input.runNW:
        game.hero.run(Direction.nw);
        break;
      case Input.runN:
        game.hero.run(Direction.n);
        break;
      case Input.runNE:
        game.hero.run(Direction.ne);
        break;
      case Input.runW:
        game.hero.run(Direction.w);
        break;
      case Input.runE:
        game.hero.run(Direction.e);
        break;
      case Input.runSW:
        game.hero.run(Direction.sw);
        break;
      case Input.runS:
        game.hero.run(Direction.s);
        break;
      case Input.runSE:
        game.hero.run(Direction.se);
        break;

      case Input.fireNW:
        _fireTowards(Direction.nw);
        break;
      case Input.fireN:
        _fireTowards(Direction.n);
        break;
      case Input.fireNE:
        _fireTowards(Direction.ne);
        break;
      case Input.fireW:
        _fireTowards(Direction.w);
        break;
      case Input.fireE:
        _fireTowards(Direction.e);
        break;
      case Input.fireSW:
        _fireTowards(Direction.sw);
        break;
      case Input.fireS:
        _fireTowards(Direction.s);
        break;
      case Input.fireSE:
        _fireTowards(Direction.se);
        break;

      case Input.fire:
        if (_lastSkill is TargetSkill) {
          var targetSkill = _lastSkill as TargetSkill;
          if (currentTarget != null) {
            // If we still have a visible target, use it.
            _fireAtTarget(_lastSkill);
          } else {
            // No current target, so ask for one.
            ui.push(new TargetDialog(this, targetSkill.getRange(game),
                (_) => _fireAtTarget(targetSkill)));
          }
        } else if (_lastSkill is DirectionSkill) {
          // Ask user to pick a direction.
          ui.push(new DirectionDialog(this, game, _fireTowards));
        } else if (_lastSkill is ActionSkill) {
          var actionSkill = _lastSkill as ActionSkill;
          game.hero.setNextAction(
              actionSkill.getAction(game, game.hero.skills[actionSkill]));
        } else {
          game.log.error("No skill selected.");
          dirty();
        }
        break;

      case Input.swap:
        if (game.hero.inventory.lastUnequipped == null) {
          game.log.error("You aren't holding an unequipped item to swap.");
          dirty();
        } else {
          action = new EquipAction(
              ItemLocation.inventory, game.hero.inventory.lastUnequipped);
        }
        break;

      case Input.wizard:
        ui.push(new WizardDialog(game));
        break;
    }

    if (action != null) game.hero.setNextAction(action);

    return true;
  }

  void closeDoor() {
    // See how many adjacent open doors there are.
    final doors = [];
    for (final direction in Direction.all) {
      final pos = game.hero.pos + direction;
      if (game.stage[pos].type.closesTo != null) {
        doors.add(pos);
      }
    }

    if (doors.length == 0) {
      game.log.error('You are not next to an open door.');
      dirty();
    } else if (doors.length == 1) {
      game.hero.setNextAction(new CloseDoorAction(doors[0]));
    } else {
      ui.push(new CloseDoorDialog(game));
    }
  }

  void pickUp() {
    var items = game.stage.itemsAt(game.hero.pos);
    if (items.length > 1) {
      // Show item dialog if there are multiple things to pick up.
      ui.push(new ItemDialog.pickUp(this));
    } else if (items.length == 1) {
      // Otherwise attempt to pick the one item.
      game.hero.setNextAction(new PickUpAction(items.first));
    } else {
      game.log.error('There is nothing here.');
      dirty();
    }
  }

  void _fireAtTarget(TargetSkill skill) {
    _lastSkill = skill;
    game.hero.setNextAction(
        skill.getTargetAction(game, game.hero.skills[skill], currentTarget));
  }

  void _fireTowards(Direction dir) {
    if (_lastSkill is DirectionSkill) {
      var directionSkill = _lastSkill as DirectionSkill;
      game.hero.setNextAction(directionSkill.getDirectionAction(
          game, game.hero.skills[directionSkill], dir));
    } else if (_lastSkill is TargetSkill) {
      var targetSkill = _lastSkill as TargetSkill;
      var pos = game.hero.pos + dir;

      // Target the monster that is in the fired direction, if any.
      Vec previous;
      for (var step in new Line(game.hero.pos, pos)) {
        // If we reached an actor, target it.
        var actor = game.stage.actorAt(step);
        if (actor != null) {
          targetActor(actor);
          break;
        }

        // If we hit a wall, target the floor tile before it.
        if (game.stage[step].blocksView) {
          targetFloor(previous);
          break;
        }

        // If we hit the end of the range, target the floor there.
        if ((step - game.hero.pos) >= targetSkill.getRange(game)) {
          targetFloor(step);
          break;
        }

        previous = step;
      }

      if (currentTarget != null) {
        game.hero.setNextAction(targetSkill.getTargetAction(
            game, game.hero.skills[targetSkill], currentTarget));
      } else {
        var tile = game.stage[game.hero.pos + dir].type.name;
        game.log.error("There is a ${tile} in the way.");
        dirty();
      }
    } else if (_lastSkill is ActionSkill) {
      game.log.error("${_lastSkill.name} does not take a direction.");
      dirty();
    } else {
      // TODO: Better error message.
      game.log.error("No skill selected.");
      dirty();
    }
  }

  void activate(Screen popped, result) {
    if (!game.hero.needsInput) {
      // The player is coming back from a screen where they selected an action
      // for the hero. Give them a bit to visually reorient themselves before
      // kicking off the action.
      _pause = 10;
    }

    if (popped is ForfeitDialog && result) {
      // Forfeiting, so exit.
      ui.pop(false);
    } else if (popped is SkillDialog) {
      // TODO: Once skills can be learned on the SkillDialog again, make this
      // work.
//      game.hero.updateSkills(result);
    } else if (popped is SelectSkillDialog && result is UsableSkill) {
      if (result is TargetSkill) {
        ui.push(new TargetDialog(
            this, result.getRange(game), (_) => _fireAtTarget(result)));
      } else if (result is DirectionSkill) {
        selectDirection(dir) {
          _lastSkill = result;
          _fireTowards(dir);
        }

        ui.push(new DirectionDialog(this, game, selectDirection));
      } else if (result is ActionSkill) {
        _lastSkill = result;
        game.hero
            .setNextAction(result.getAction(game, game.hero.skills[result]));
      }
    }
  }

  void update() {
    if (_pause > 0) {
      _pause--;
      return;
    }

    if (_effects.length > 0) dirty();

    var result = game.update();

    // See if the hero died.
    if (!game.hero.isAlive) {
      ui.goTo(new GameOverScreen(game.log));
      return;
    }

    if (game.hero.dazzle.isActive) dirty();

    for (final event in result.events) addEffects(_effects, event);

    if (result.needsRefresh) dirty();

    _effects = _effects.where((effect) => effect.update(game)).toList();
    _positionCamera();
  }

  void render(Terminal terminal) {
    terminal.clear();

    var bar =
        new Glyph.fromCharCode(CharCode.boxDrawingsLightVertical, steelGray);
    for (var y = 0; y < terminal.height; y++) {
      terminal.drawGlyph(60, y, bar);
    }

    var hero = game.hero;
    var heroColor = ash;
    if (hero.health < hero.maxHealth / 4) {
      heroColor = brickRed;
    } else if (hero.poison.isActive) {
      heroColor = peaGreen;
    } else if (hero.cold.isActive) {
      heroColor = cornflower;
    } else if (hero.health < hero.maxHealth / 2) {
      heroColor = salmon;
    }

    var visibleMonsters = <Monster>[];

    _drawStage(terminal.rect(0, 0, viewSize.x, viewSize.y), heroColor,
        visibleMonsters);

    _drawLog(terminal.rect(0, 34, 60, 6));
    _drawSidebar(terminal.rect(61, 0, 20, 40), heroColor, visibleMonsters);
  }

  /// Draws [Glyph] at [x], [y] in [Stage] coordinates onto the current view.
  void drawStageGlyph(Terminal terminal, int x, int y, Glyph glyph) {
    terminal.drawGlyph(x - _cameraBounds.x, y - _cameraBounds.y, glyph);
  }

  /// Determines which portion of the [Stage] should be in view based on the
  /// position of the [Hero].
  void _positionCamera() {
    // Handle the stage being smaller than the view.
    var rangeWidth = math.max(0, game.stage.width - viewSize.x);
    var rangeHeight = math.max(0, game.stage.height - viewSize.y);

    var cameraRange = new Rect(0, 0, rangeWidth, rangeHeight);

    var camera = game.hero.pos - viewSize ~/ 2;
    camera = cameraRange.clamp(camera);
    _cameraBounds = new Rect(
        camera.x,
        camera.y,
        math.min(viewSize.x, game.stage.width),
        math.min(viewSize.y, game.stage.height));
  }

  static const _dazzleColors = const [
    steelGray,
    slate,
    gunsmoke,
    ash,
    sandal,
    persimmon,
    copper,
    garnet,
    buttermilk,
    gold,
    carrot,
    mint,
    mustard,
    lima,
    peaGreen,
    sherwood,
    salmon,
    brickRed,
    maroon,
    lilac,
    violet,
    indigo,
    turquoise,
    cornflower,
    cerulean,
    ultramarine,
  ];

  void _drawStage(
      Terminal terminal, Color heroColor, List<Monster> visibleMonsters) {
    var hero = game.hero;

    // Draw the tiles and items.
    for (var pos in _cameraBounds) {
      var tile = game.stage[pos];
      if (tile.isExplored) {
        var tileGlyph = tile.type.appearance as Glyph;
        var char = tileGlyph.char;
        var lightFore = tileGlyph.fore;
        var lightBack = tileGlyph.back;

        var darkFore = lightFore.blend(nearBlack, 0.8);
        var darkBack = lightBack.blend(nearBlack, 0.8);

        var items = game.stage.itemsAt(pos);
        if (items.isNotEmpty) {
          var itemGlyph = items.first.appearance;
          char = itemGlyph.char;
          lightFore = itemGlyph.fore;
          darkFore = itemGlyph.fore;
        }

        // The hero is always visible, even in the dark.
        if (tile.isVisible || pos == game.hero.pos) {
          var actor = game.stage.actorAt(pos);
          if (actor != null) {
            var actorGlyph = actor.appearance;
            if (actorGlyph is Glyph) {
              char = actorGlyph.char;
              lightFore = actorGlyph.fore;
              darkFore = actorGlyph.fore;
            } else {
              // Hero.
              char = CharCode.at;
              lightFore = heroColor;
              darkFore = heroColor;
            }

            // If the actor is being targeted, invert its colors.
            if (targetActor == actor) {
              lightBack = lightFore;
              darkBack = darkFore;
              lightFore = midnight;
              darkFore = midnight;
            }

            if (actor is Monster) visibleMonsters.add(actor);
          }
        }

        if (hero.dazzle.isActive) {
          var chance = math.min(90, hero.dazzle.duration * 8);
          if (!rng.percent(chance)) {
            char = rng.percent(chance) ? char : CharCode.asterisk;
            lightFore = rng.item(_dazzleColors);
            darkFore = lightFore;
          }
        }

        Color fore;
        Color back;
        if (tile.isVisible) {
          // The light values actually range up to [Lighting.max], but we scale
          // to a shorter range to make even partially illuminated tiles bright.
          // Otherwise, the game is too gloomy looking.
          var light = (tile.illumination / 128).clamp(0, 1);

          fore = darkFore.blend(lightFore, light);
          back = darkBack.blend(lightBack, light);
        } else {
          fore = darkFore;
          back = darkBack.blend(Color.black, 0.5);
        }

        // TODO: Warm additive glow for brightest tiles. Maybe treat glow as
        // a separate layer. Certain tiles, independent of their actual
        // illumination, also have a glow value. (So, for example, a lit room
        // might be illuminated all over, but only glow at the torch sconces).
        // Glow would have a few tiles of surrounding fade, like light. But it
        // also bleeds over walls and is additively applied to the rendered
        // color. Sort of a faux HDR.

        var glyph = new Glyph.fromCharCode(char, fore, back);
        drawStageGlyph(terminal, pos.x, pos.y, glyph);
      }
    }

    // Draw the effects.
    for (var effect in _effects) {
      effect.render(game, (x, y, glyph) {
        drawStageGlyph(terminal, x, y, glyph);
      });
    }
  }

  void _drawLog(Terminal terminal) {
    var y = 0;

    for (final message in game.log.messages) {
      var color;
      switch (message.type) {
        case LogType.message:
          color = gunsmoke;
          break;
        case LogType.error:
          color = brickRed;
          break;
        case LogType.quest:
          color = violet;
          break;
        case LogType.gain:
          color = gold;
          break;
        case LogType.help:
          color = peaGreen;
          break;
      }

      terminal.writeAt(0, y, message.text, color);
      if (message.count > 1) {
        terminal.writeAt(
            message.text.length, y, ' (x${message.count})', steelGray);
      }
      y++;
    }
  }

  void _drawSidebar(
      Terminal terminal, Color heroColor, List<Monster> visibleMonsters) {
    var hero = game.hero;
    _drawStat(
        terminal, 0, 'Health', hero.health, brickRed, hero.maxHealth, maroon);
    terminal.writeAt(0, 1, 'Food', UIHue.helpText);
    terminal.writeAt(10, 1, hero.food.ceil().toString(), persimmon);

    _drawStat(terminal, 2, 'Level', hero.level, cerulean);
    if (hero.level < Hero.maxLevel) {
      var levelPercent = 100 *
          (hero.experience - calculateLevelCost(hero.level)) ~/
          (calculateLevelCost(hero.level + 1) - calculateLevelCost(hero.level));
      terminal.writeAt(15, 2, '$levelPercent%', ultramarine);
    }

    var y = 4;
    drawStat(StatBase stat) {
      terminal.writeAt(0, y, stat.name, UIHue.helpText);
      terminal.writeAt(10, y, stat.value.toString(), ash);
      y++;
    }

    drawStat(hero.strength);
    drawStat(hero.agility);
    drawStat(hero.fortitude);
    drawStat(hero.intellect);
    drawStat(hero.will);

    terminal.writeAt(0, 10, 'Focus', UIHue.helpText);

    Draw.meter(terminal, 9, 10, 10, hero.focus, Option.maxFocus, cerulean,
        ultramarine);

    _drawStat(terminal, 12, 'Armor',
        '${(100 - getArmorMultiplier(hero.armor) * 100).toInt()}% ', peaGreen);
    // TODO: Show the weapon and stats better.
    var hit = hero.createMeleeHit(null);
    _drawStat(terminal, 13, 'Weapon', hit.damageString, turquoise);

    // Draw the nearby monsters.
    terminal.writeAt(0, 16, '@', heroColor);
    terminal.writeAt(2, 16, _save.name, UIHue.text);
    _drawHealthBar(terminal, 17, hero);

    visibleMonsters.sort((a, b) {
      var aDistance = (a.pos - game.hero.pos).lengthSquared;
      var bDistance = (b.pos - game.hero.pos).lengthSquared;
      return aDistance.compareTo(bDistance);
    });

    for (var i = 0; i < 10; i++) {
      var y = 18 + i * 2;
      if (i < visibleMonsters.length) {
        var monster = visibleMonsters[i];

        var glyph = monster.appearance as Glyph;
        if (targetActor == monster) {
          glyph = new Glyph.fromCharCode(glyph.char, glyph.back, glyph.fore);
        }

        terminal.drawGlyph(0, y, glyph);
        terminal.writeAt(2, y, monster.breed.name,
            (targetActor == monster) ? UIHue.selection : UIHue.text);

        _drawHealthBar(terminal, y + 1, monster);
      }
    }

    // Draw the unseen items.
    terminal.writeAt(0, 38, "Unfound items:", UIHue.helpText);
    var unseen = <Item>[];
    game.stage.forEachItem((item, pos) {
      if (!game.stage[pos].isExplored) unseen.add(item);
    });

    // Show the "best" ones first.
    unseen.sort();

    var x = 0;
    var lastGlyph;
    for (var item in unseen.reversed) {
      if (item.appearance != lastGlyph) {
        terminal.drawGlyph(x, 39, item.appearance);
        x++;
        if (x >= terminal.width) break;
        lastGlyph = item.appearance;
      }
    }
  }

  /// Draws a labeled numeric stat.
  void _drawStat(
      Terminal terminal, int y, String label, value, Color valueColor,
      [max, Color maxColor]) {
    terminal.writeAt(0, y, label, UIHue.helpText);
    var valueString = value.toString();
    terminal.writeAt(10, y, valueString, valueColor);

    if (max != null) {
      terminal.writeAt(10 + valueString.length, y, ' / $max', maxColor);
    }
  }

  static final _resistConditions = {
    Elements.air: ["A", Color.black, turquoise],
    Elements.earth: ["E", Color.black, persimmon],
    Elements.fire: ["F", Color.black, brickRed],
    Elements.water: ["W", Color.black, ultramarine],
    Elements.acid: ["A", Color.black, lima],
    Elements.cold: ["C", Color.black, cornflower],
    Elements.lightning: ["L", Color.black, lilac],
    Elements.poison: ["P", Color.black, peaGreen],
    Elements.dark: ["D", Color.black, steelGray],
    Elements.light: ["L", Color.black, buttermilk],
    Elements.spirit: ["S", Color.black, violet]
  };

  /// Draws a health bar for [actor].
  void _drawHealthBar(Terminal terminal, int y, Actor actor) {
    // Show conditions.
    var conditions = [];

    if (actor is Monster && actor.isAfraid) {
      conditions.add(["!", sandal]);
    }

    if (actor.poison.isActive) {
      switch (actor.poison.intensity) {
        case 1:
          conditions.add(["P", sherwood]);
          break;
        case 2:
          conditions.add(["P", peaGreen]);
          break;
        default:
          conditions.add(["P", mint]);
          break;
      }
    }

    if (actor.cold.isActive) conditions.add(["C", cornflower]);
    switch (actor.haste.intensity) {
      case 1:
        conditions.add(["S", persimmon]);
        break;
      case 2:
        conditions.add(["S", gold]);
        break;
      case 3:
        conditions.add(["S", buttermilk]);
        break;
    }

    if (actor.blindness.isActive) conditions.add(["B", steelGray]);
    if (actor.dazzle.isActive) conditions.add(["D", lilac]);

    for (var element in game.content.elements) {
      if (actor.resistances[element].isActive) {
        conditions.add(_resistConditions[element]);
      }
    }

    var x = 2;
    for (var condition in conditions.take(6)) {
      if (condition.length == 3) {
        terminal.writeAt(x, y, condition[0], condition[1], condition[2]);
      } else {
        terminal.writeAt(x, y, condition[0], condition[1]);
      }
      x++;
    }

    Draw.meter(
        terminal, 9, y, 10, actor.health, actor.maxHealth, brickRed, maroon);
  }
}
