package skua.module
{
	import flash.filters.GlowFilter;

	public class SelfOutline extends Module
	{
		private var _lastPMC:* = null;
		private var _color:int = 0;

		// 0=none, 1=Cyan, 2=White, 3=Gold, 4=Green, 5=Red, 6=Blue, 7=Purple, 8=Pink
		private static const COLORS:Array = [0, 0x00EEFF, 0xFFFFFF, 0xFFCC00, 0x00FF44, 0xFF2200, 0x4488FF, 0xCC00FF, 0xFF44AA];

		public function SelfOutline() { super("SelfOutline"); }

		public function setColor(n:int):void
		{
			_color   = n;
			_lastPMC = null;
		}

		override public function onToggle(game:*):void
		{
			if (!enabled) clear(game);
		}

		override public function onFrame(game:*):void
		{
			try
			{
				var pMC:* = game.world.myAvatar.pMC;
				if (pMC === _lastPMC) return;
				_lastPMC = pMC;
				if (!pMC) return;
				if (_color > 0 && _color < COLORS.length)
					pMC.filters = [new GlowFilter(COLORS[_color], 1.0, 3, 3, 8, 1)];
				else
					pMC.filters = [];
			}
			catch (e:Error) { _lastPMC = null; }
		}

		private function clear(game:*):void
		{
			try
			{
				var pMC:* = game.world.myAvatar.pMC;
				if (pMC) pMC.filters = [];
			}
			catch (e:Error) {}
			_lastPMC = null;
		}
	}
}
