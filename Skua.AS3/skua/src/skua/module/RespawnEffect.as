package skua.module
{
	import flash.display.DisplayObjectContainer;
	import flash.display.GradientType;
	import flash.display.Sprite;
	import flash.geom.ColorTransform;
	import flash.geom.Matrix;

	/**
	 * Cosmetic burst where a player (self or anyone else, any map) materializes
	 * back in after dying — detected the same way KillFlash/DeathDetector detect
	 * a death (dataLeaf.intHP falling to/from zero), just watching for the
	 * reverse transition (dead → alive) instead.
	 *
	 * The burst is a throwaway Sprite added as a sibling of the avatar's own pMC
	 * (same parent, positioned at its x/y) so it appears right where they pop
	 * back in, plus a brief white color-pulse on pMC itself for a "flash-in"
	 * feel — both purely additive and self-removing over their TTL, no lasting
	 * state on the avatar.
	 */
	public class RespawnEffect extends Module
	{
		private static const ALLY_GLOW:uint    = 0x3FA0FF;
		private static const ENEMY_GLOW:uint   = 0xFF4F4F;
		private static const NEUTRAL_GLOW:uint = 0xFFD24D;

		private static const TTL:int = 24;

		private var _lastHP:Object = {};
		private var _dead:Object   = {};
		private var _bursts:Array  = [];

		public function RespawnEffect() { super("RespawnEffect"); }

		override public function onToggle(game:*):void
		{
			if (!enabled)
			{
				for (var i:int = _bursts.length - 1; i >= 0; i--)
					removeBurst(_bursts[i]);
				_bursts  = [];
				_lastHP  = {};
				_dead    = {};
			}
		}

		override public function onFrame(game:*):void
		{
			if (!enabled) return;
			scanRespawns(game);
			tickBursts();
		}

		private function scanRespawns(game:*):void
		{
			var myTeam:* = null;
			try { myTeam = game.world.myAvatar.objData.strTeam; } catch (e:Error) {}

			try { checkAvatar("self", game.world.myAvatar, myTeam, myTeam); }
			catch (e:Error) {}

			try
			{
				for (var aid:* in game.world.avatars)
				{
					var av:* = game.world.avatars[aid];
					if (!av || av.isMyAvatar) continue;

					var theirTeam:* = null;
					try { theirTeam = av.objData.strTeam; } catch (e2:Error) {}
					checkAvatar(String(aid), av, myTeam, theirTeam);
				}
			}
			catch (e:Error) {}
		}

		private function checkAvatar(key:String, av:*, myTeam:*, theirTeam:*):void
		{
			if (av == null) return;
			var hp:Number;
			try { hp = Number(av.dataLeaf.intHP); }
			catch (e:Error) { return; } // avatar not fully loaded — don't touch its tracked state

			var wasDead:Boolean = (_dead[key] == true);

			if (hp <= 0)
			{
				_dead[key] = true;
			}
			else if (wasDead)
			{
				delete _dead[key];
				spawnBurst(av, colorFor(myTeam, theirTeam));
			}
			_lastHP[key] = hp;
		}

		private function colorFor(myTeam:*, theirTeam:*):uint
		{
			if (myTeam == null || theirTeam == null) return NEUTRAL_GLOW;
			return (theirTeam == myTeam) ? ALLY_GLOW : ENEMY_GLOW;
		}

		private function spawnBurst(av:*, color:uint):void
		{
			try
			{
				var pmc:* = av.pMC;
				if (!pmc) return;
				var parent:DisplayObjectContainer = pmc.parent as DisplayObjectContainer;
				if (!parent) return;

				var fx:Sprite = new Sprite();
				fx.mouseEnabled  = false;
				fx.mouseChildren = false;
				fx.x = pmc.x;
				fx.y = pmc.y;
				parent.addChild(fx);

				_bursts.push({ fx: fx, pmc: pmc, ttl: TTL, color: color });
			}
			catch (e:Error) {}
		}

		private function tickBursts():void
		{
			for (var i:int = _bursts.length - 1; i >= 0; i--)
			{
				var b:* = _bursts[i];
				b.ttl--;

				if (b.ttl <= 0 || b.fx.parent == null)
				{
					removeBurst(b);
					continue;
				}

				try
				{
					var t:Number = Number(b.ttl) / TTL;  // 1 -> 0
					var p:Number = 1 - t;                // 0 -> 1 (progress)

					var g:* = b.fx.graphics;
					g.clear();

					// Expanding ring shockwave, fading as it grows
					g.lineStyle(3, b.color, t);
					g.drawCircle(0, -22, 10 + p * 34);

					// Vertical "materialize" beam, tallest at the start, fading with t
					var beamH:Number = 55;
					var m:Matrix = new Matrix();
					m.createGradientBox(18, beamH, Math.PI / 2, -9, -beamH - 4);
					g.beginGradientFill(GradientType.LINEAR, [b.color, b.color], [0, t * 0.5], [0, 255], m);
					g.drawRect(-9, -beamH - 4, 18, beamH);
					g.endFill();

					// Brief white flash-in on the avatar itself
					var w:Number = 220 * t;
					b.pmc.transform.colorTransform = new ColorTransform(1, 1, 1, 1, w, w, w, 0);
				}
				catch (e:Error) { removeBurst(b); }
			}
		}

		private function removeBurst(b:*):void
		{
			try { if (b.fx && b.fx.parent) b.fx.parent.removeChild(b.fx); } catch (e:Error) {}
			try { b.pmc.transform.colorTransform = new ColorTransform(); } catch (e2:Error) {}

			var idx:int = _bursts.indexOf(b);
			if (idx >= 0) _bursts.splice(idx, 1);
		}
	}
}
