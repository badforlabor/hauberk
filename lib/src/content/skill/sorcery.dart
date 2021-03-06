import 'package:piecemeal/src/vec.dart';

import '../../engine.dart';

import '../action/bolt.dart';
import '../action/ray.dart';
import '../elements.dart';

class Icicle extends Spell implements TargetSkill {
  String get description => "Launches a spear-like icicle.";

  String get name => "Icicle";

  int get baseComplexity => 10;

  int get baseFocusCost => 200;

  int get damage => 7;
  int get range => 8;

  num getRange(Game game) => range;

  Action onGetTargetAction(Game game, Vec target) {
    var attack = new Attack(
        new Noun("the icicle"), "pierce", damage, range, Elements.cold);
    return new BoltAction(target, attack.createHit());
  }
}

class Windstorm extends Spell implements ActionSkill {
  String get description =>
      "Summons a blast of air, spreading out from the sorceror.";

  String get name => "Windstorm";

  int get baseComplexity => 14;

  int get baseFocusCost => 400;

  int get damage => 5;
  int get range => 6;

  bool canUse(Game game) => true;

  Action onGetAction(Game game) {
    var attack =
        new Attack(new Noun("the wind"), "blast", damage, range, Elements.air);
    return new RayAction.ring(game.hero.pos, attack.createHit());
  }
}
