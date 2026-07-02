package skua.module
{
	import flash.filters.GlowFilter;

	public class HighlightEnemies extends Module
	{
		// Outer glow only — leaves character art untouched, adds coloured halo.
		private static const GREEN:Array = [new GlowFilter(0x22FF22, 0.85, 16, 16, 2, 1, false, false)];
		private static const NONE:Array  = [];
		private var _enemyFilters:Array  = [new GlowFilter(0xFF3333, 0.85, 16, 16, 2, 1, false, false)];

		// Called from C# via setHighlightConfig Flash bridge.
		public function setConfig(color:uint, intensity:int):void
		{
			var a:Number = Math.max(0.01, Math.min(1.0, intensity / 100.0));
			var blur:Number = 8 + a * 12; // 8–20
			_enemyFilters = [new GlowFilter(color, a, blur, blur, 2, 1, false, false)];
		}

		public function HighlightEnemies()
		{
			super("HighlightEnemies");
		}

		override public function onToggle(game:*):void
		{
			if (!enabled)
			{
				for (var aid:* in game.world.avatars)
				{
					var avatar:* = game.world.avatars[aid];
					try { if (avatar && avatar.pMC) avatar.pMC.filters = NONE; }
					catch (e:Error) {}
				}
				return;
			}
			apply(game);
		}

		override public function onFrame(game:*):void
		{
			apply(game);
		}

		private function apply(game:*):void
		{
			for (var aid:* in game.world.avatars)
			{
				var avatar:* = game.world.avatars[aid];
				try
				{
					if (!avatar || !avatar.pMC) continue;

					if (avatar.isMyAvatar)
					{
						avatar.pMC.filters = NONE;
						continue;
					}

					var aName:String = "";
					try { aName = String(avatar.objData.strUsername).toLowerCase(); } catch (e:Error) {}
					// Green for confirmed teammates; no glow for unknowns (can't confirm enemy status).
					avatar.pMC.filters = TeammateRoster.isTeammate(aName) ? GREEN : _enemyFilters;
				}
				catch (e:Error) {}
			}
		}
	}
}
