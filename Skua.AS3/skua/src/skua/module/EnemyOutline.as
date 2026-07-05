package skua.module
{
	import flash.filters.GlowFilter;

	public class EnemyOutline extends Module
	{
		private var _color:int       = 1;
		private var _lastPMCs:Object = {};

		// 0=none, 1=Red, 2=Orange, 3=White, 4=Gold, 5=Purple, 6=Magenta, 7=Green, 8=Cyan
		private static const COLORS:Array = [0, 0xFF2200, 0xFF8800, 0xFFFFFF, 0xFFCC00, 0xAA00FF, 0xFF00AA, 0x00FF66, 0x00EEFF];

		public function EnemyOutline() { super("EnemyOutline"); }

		public function setColor(n:int):void
		{
			_color    = n;
			_lastPMCs = {};
		}

		override public function onToggle(game:*):void
		{
			if (!enabled) clearAll(game);
		}

		override public function onFrame(game:*):void
		{
			if (_color <= 0 || _color >= COLORS.length) return;
			var col:uint = uint(COLORS[_color]);

			var myTeam:* = null;
			try { myTeam = game.world.myAvatar.objData.strTeam; } catch (e:Error) {}

			try
			{
				for (var aid:* in game.world.avatars)
				{
					var av:* = game.world.avatars[aid];
					try
					{
						if (!av || av.isMyAvatar || !av.pMC) continue;
						if (myTeam != null)
						{
							try { if (av.objData.strTeam == myTeam) continue; } catch (e2:Error) {}
						}
						if (_lastPMCs[aid] !== av.pMC)
						{
							_lastPMCs[aid] = av.pMC;
							av.pMC.filters = [new GlowFilter(col, 1.0, 3, 3, 8, 1)];
						}
					}
					catch (e:Error) {}
				}
			}
			catch (e:Error) {}
		}

		private function clearAll(game:*):void
		{
			try
			{
				for (var aid:* in game.world.avatars)
				{
					var av:* = game.world.avatars[aid];
					try
					{
						if (!av || av.isMyAvatar || !av.pMC) continue;
						av.pMC.filters = [];
					}
					catch (e:Error) {}
				}
			}
			catch (e:Error) {}
			_lastPMCs = {};
		}
	}
}
