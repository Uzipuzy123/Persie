package skua.module
{
	import flash.display.DisplayObjectContainer;
	import flash.display.GradientType;
	import flash.display.Sprite;
	import flash.geom.Matrix;

	/**
	 * Cosmetic portal-materialize burst played wherever the avatar lands after
	 * every same-map cell (room) transition — e.g. BludRutBrawl's Enter0 ->
	 * Morale0C hop. Originally conceived as a beacon glued to the door/arrow
	 * trigger itself, but a live DebugPanel REC capture (walking Enter0 ->
	 * Morale0C) showed no such object exists: the whole map has one generic
	 * "btnWalkingArea" ground-click button and curRoom never changes, only
	 * world.strFrame — there's nothing distinct to decorate. This instead
	 * watches for that strFrame flip and fires the burst at the destination
	 * once the avatar has actually snapped there.
	 *
	 * The native reposition takes ~100ms after strFrame flips (see
	 * FastDoorEnter's docstring) — same real mechanism whether or not
	 * FastDoorEnter itself is enabled, just faster with it on. Waiting
	 * ARRIVAL_DELAY_FRAMES after the flip covers both cases without needing
	 * to know which is active.
	 */
	public class PortalFlash extends Module
	{
		private static const PORTAL_GLOW:uint = 0x33CCFF;

		private static const ARRIVAL_DELAY_FRAMES:int = 5;
		private static const TTL:int = 24;

		private var _lastCell:String    = "";
		private var _armed:Boolean      = false;
		private var _armCountdown:int   = 0;
		private var _bursts:Array       = [];

		public function PortalFlash() { super("PortalFlash"); }

		override public function onToggle(game:*):void
		{
			_lastCell = "";
			_armed    = false;
			if (!enabled)
			{
				for (var i:int = _bursts.length - 1; i >= 0; i--)
					removeBurst(_bursts[i]);
				_bursts = [];
			}
		}

		override public function onFrame(game:*):void
		{
			if (!enabled) return;
			try
			{
				var cell:String = "";
				try { cell = game.world.strFrame; } catch (e:Error) {}

				if (cell != _lastCell)
				{
					// Skip the very first observed cell (module just enabled / avatar
					// just spawned) — only real transitions after that should flash.
					if (_lastCell.length > 0)
					{
						_armed        = true;
						_armCountdown = ARRIVAL_DELAY_FRAMES;
					}
					_lastCell = cell;
				}

				if (_armed)
				{
					_armCountdown--;
					if (_armCountdown <= 0)
					{
						_armed = false;
						spawnBurst(game);
					}
				}
			}
			catch (e:Error) {}

			tickBursts();
		}

		private function spawnBurst(game:*):void
		{
			try
			{
				var pmc:* = game.world.myAvatar.pMC;
				if (!pmc) return;
				var parent:DisplayObjectContainer = pmc.parent as DisplayObjectContainer;
				if (!parent) return;

				var fx:Sprite = new Sprite();
				fx.mouseEnabled  = false;
				fx.mouseChildren = false;
				fx.x = pmc.x;
				fx.y = pmc.y;
				parent.addChild(fx);

				_bursts.push({ fx: fx, ttl: TTL });
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
					var t:Number = Number(b.ttl) / TTL; // 1 -> 0
					var p:Number = 1 - t;                // 0 -> 1

					var g:* = b.fx.graphics;
					g.clear();

					// Expanding ring shockwave
					g.lineStyle(3, PORTAL_GLOW, t);
					g.drawCircle(0, -22, 8 + p * 40);

					// Rising materialize beam, tallest at start, fading with t
					var beamH:Number = 60;
					var m:Matrix = new Matrix();
					m.createGradientBox(20, beamH, Math.PI / 2, -10, -beamH - 4);
					g.beginGradientFill(GradientType.LINEAR, [PORTAL_GLOW, PORTAL_GLOW], [0, t * 0.55], [0, 255], m);
					g.drawRect(-10, -beamH - 4, 20, beamH);
					g.endFill();

					// Bright inner flash at the base, quick to fade
					g.beginFill(0xFFFFFF, t * t * 0.7);
					g.drawCircle(0, -18, 14);
					g.endFill();
				}
				catch (e:Error) { removeBurst(b); }
			}
		}

		private function removeBurst(b:*):void
		{
			try { if (b.fx && b.fx.parent) b.fx.parent.removeChild(b.fx); } catch (e:Error) {}
			var idx:int = _bursts.indexOf(b);
			if (idx >= 0) _bursts.splice(idx, 1);
		}
	}
}
