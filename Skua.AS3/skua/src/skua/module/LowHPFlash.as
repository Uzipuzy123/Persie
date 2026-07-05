package skua.module
{
	import flash.geom.ColorTransform;

	public class LowHPFlash extends Module
	{
		private var _pulse:Number   = 0;
		private var _applied:Boolean = false;

		private static const THRESHOLD:Number = 0.50;

		public function LowHPFlash() { super("LowHPFlash"); }

		override public function onToggle(game:*):void
		{
			if (!enabled) resetTransform(game);
		}

		override public function onFrame(game:*):void
		{
			var ratio:Number = hpRatio(game);

			if (ratio <= 0.0 || ratio > THRESHOLD)
			{
				if (_applied) resetTransform(game);
				return;
			}

			// 0.0 at 30% HP → 1.0 at 0% HP
			var danger:Number = 1.0 - (ratio / THRESHOLD);

			_pulse += 0.04 + danger * 0.13;
			if (_pulse > 6.2832) _pulse -= 6.2832;

			// Sine pulse 0 → 1
			var pulseFactor:Number = (Math.sin(_pulse) + 1.0) * 0.5;

			// intensity: how red the character looks at this moment
			var intensity:Number = danger * pulseFactor;

			try
			{
				var ct:ColorTransform = new ColorTransform();
				ct.redMultiplier   = 1.0;
				ct.greenMultiplier = 1.0 - intensity * 0.80;
				ct.blueMultiplier  = 1.0 - intensity * 0.80;
				ct.redOffset       = int(intensity * 55);
				game.world.myAvatar.pMC.transform.colorTransform = ct;
				_applied = true;
			}
			catch (e:Error) {}
		}

		private function resetTransform(game:*):void
		{
			try { game.world.myAvatar.pMC.transform.colorTransform = new ColorTransform(); }
			catch (e:Error) {}
			_applied = false;
			_pulse   = 0;
		}

		private function hpRatio(game:*):Number
		{
			try
			{
				var hp:int    = int(game.world.myAvatar.dataLeaf.intHP);
				var maxHP:int = int(game.world.myAvatar.dataLeaf.intHPMax);
				if (maxHP <= 0) return 1.0;
				return hp / maxHP;
			}
			catch (e:Error) {}
			return 1.0;
		}
	}
}
