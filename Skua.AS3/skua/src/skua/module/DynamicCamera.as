package skua.module
{
	// Light reactive-camera experiment: zooms game.world in slightly while
	// you have a target selected, eases back to normal when you don't.
	// AQW's native camera is a fixed flat view of a single-screen room — this
	// tests whether an *active* camera (something that responds to combat
	// state) feels meaningfully different, separate from FovControl's
	// standalone persistent zoom slider (no connection between the two —
	// each writes world.scaleX/scaleY independently; don't run both at once,
	// they'll fight over the same property every frame).
	//
	// "In combat" signal here is just myAvatar.target != null (excluding
	// self-targeting from heals/buffs) — the simplest available client-side
	// flag, not wired to actual damage/packet events.
	//
	// Pure scale only — deliberately does NOT touch world.x/world.y (an
	// earlier version re-centered on the player each frame, which let the
	// view drift out of the room's bounds when not near center).
	public class DynamicCamera extends Module
	{
		private static const ZOOM_IN:Number = 1.12;
		private static const EASE:Number    = 0.08;

		// How close _currentZoom needs to get to 1.0 before we stop easing
		// and hard-snap to exactly 1.0 instead — the asymptotic ease below
		// technically never reaches exactly 1.0, just gets closer forever.
		private static const SNAP_EPSILON:Number = 0.002;

		private var _currentZoom:Number = 1.0;

		public function DynamicCamera() { super("DynamicCamera"); }

		override public function onToggle(game:*):void
		{
			if (enabled) _currentZoom = 1.0;
			else restore(game);
		}

		override public function onFrame(game:*):void
		{
			if (!enabled) return;
			try
			{
				var world:* = game.world;
				var myAvatar:* = world.myAvatar;
				if (myAvatar == null) return;

				// Self-heals/buffs target yourself (myAvatar.target === myAvatar)
				// — that's not a combat engagement, so it shouldn't trigger the
				// zoom the way targeting an enemy player or monster does.
				var hasTarget:Boolean = false;
				try { hasTarget = (myAvatar.target != null) && (myAvatar.target !== myAvatar); } catch (e:Error) {}

				if (!hasTarget && Math.abs(_currentZoom - 1.0) < SNAP_EPSILON)
				{
					_currentZoom = 1.0;
					world.scaleX = 1.0;
					world.scaleY = 1.0;
					return;
				}

				var targetZoom:Number = hasTarget ? ZOOM_IN : 1.0;
				_currentZoom += (targetZoom - _currentZoom) * EASE;
				world.scaleX = _currentZoom;
				world.scaleY = _currentZoom;
			}
			catch (e:Error) {}
		}

		private function restore(game:*):void
		{
			try { game.world.scaleX = 1.0; game.world.scaleY = 1.0; }
			catch (e:Error) {}
			_currentZoom = 1.0;
		}
	}
}
