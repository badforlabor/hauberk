import 'package:piecemeal/piecemeal.dart';

import 'action.dart';
import 'attack.dart';
import '../core/game.dart';
import '../hero/hero.dart';
import '../stage/sound.dart';

class WalkAction extends Action {
  final Direction dir;
  final bool _isRunning;

  WalkAction(this.dir, {bool running: false}) : _isRunning = running;

  ActionResult onPerform() {
    // Rest if we aren't moving anywhere.
    if (dir == Direction.none) {
      return alternate(new RestAction());
    }

    var pos = actor.pos + dir;

    // See if there is an actor there.
    final target = game.stage.actorAt(pos);
    if (target != null && target != actor) {
      return alternate(new AttackAction(target));
    }

    // See if it's a door.
    var tile = game.stage[pos].type;
    if (tile.opensTo != null) {
      return alternate(new OpenDoorAction(pos));
    }

    // See if we can walk there.
    if (!actor.canOccupy(pos)) {
      // If the hero runs into something in the dark, they can figure out what
      // it is.
      if (actor is Hero) {
        game.hero.explore(game.stage.explore(pos, force: true));
      }

      return fail('{1} hit[s] the ${tile.name}.', actor);
    }

    actor.pos = pos;

    // See if the hero stepped on anything interesting.
    if (actor is Hero) {
      for (var item in game.stage.itemsAt(pos).toList()) {
        hero.disturb();

        // Treasure is immediately, freely acquired.
        if (item.isTreasure) {
          // Pick a random value near the price.
          var min = (item.price * 0.5).ceil();
          var max = (item.price * 1.5).ceil();
          var value = rng.range(min, max);
          hero.gold += value;
          log("{1} pick[s] up {2} worth $value gold.", hero, item);
          game.stage.removeItem(item, pos);

          addEvent(EventType.gold, actor: actor, pos: actor.pos, other: item);
        } else {
          log('{1} [are|is] standing on {2}.', actor, item);
        }
      }

      // If we ran next to an item, note it and disturb. That way we stop where
      // the player can see it more easily.
      if (_isRunning) {
        for (var neighborDir in [dir.rotateLeft45, dir, dir.rotateRight45]) {
          var neighbor = pos + neighborDir;
          for (var item in hero.game.stage.itemsAt(neighbor)) {
            hero.disturb();
            hero.game.log.message('{1} [are|is] are next to {2}.', hero, item);
          }
        }
      }

      hero.focus += 50;
    }

    return succeed();
  }

  String toString() => '$actor walks $dir';
}

class OpenDoorAction extends Action {
  final Vec doorPos;

  OpenDoorAction(this.doorPos);

  ActionResult onPerform() {
    game.stage[doorPos].type = game.stage[doorPos].type.opensTo;
    game.stage.tileOpacityChanged();

    return succeed('{1} open[s] the door.', actor);
  }
}

class CloseDoorAction extends Action {
  final Vec doorPos;

  CloseDoorAction(this.doorPos);

  ActionResult onPerform() {
    var blockingActor = game.stage.actorAt(doorPos);
    if (blockingActor != null) {
      return fail("{1} [are|is] in the way!", blockingActor);
    }

    // TODO: What should happen if items are on the tile?
    game.stage[doorPos].type = game.stage[doorPos].type.closesTo;
    game.stage.tileOpacityChanged();

    return succeed('{1} close[s] the door.', actor);
  }
}

/// Action for doing nothing for a turn.
class RestAction extends Action {
  ActionResult onPerform() {
    if (actor is Hero) {
      _eatFood();

      // Have this amount increase over successive resting turns?
      hero.focus += 100;
    } else if (!actor.isVisibleToHero) {
      // Monsters can rest if out of sight.
      actor.health++;
    }

    return succeed();
  }

  /// Regenerates health when the hero rests, if possible.
  void _eatFood() {
    if (hero.food <= 0) return;
    if (hero.poison.isActive) return;
    if (hero.health == hero.maxHealth) return;

    hero.food--;
    hero.health++;
  }

  double get noise => Sound.restNoise;
}
