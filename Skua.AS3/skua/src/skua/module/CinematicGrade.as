package skua.module
{
	import flash.filters.ColorMatrixFilter;

	// Full-screen color grade over the game world (map/avatars/monsters) —
	// deeper contrast, slightly desaturated toward a filmic look, warm
	// highlights / cool shadows. Deliberately a single ColorMatrixFilter
	// (one combined matrix, built by multiplying contrast+saturation+tint
	// matrices together in buildMatrix() rather than stacking three separate
	// ColorMatrixFilter instances in the filters array) — chaining multiple
	// filters forces a separate rasterize pass each, which is real cost on a
	// 30fps game; one matrix is one pass.
	//
	// Applied to game.world specifically, not game.stage/game itself — Stage
	// isn't a DisplayObject and has no .filters property, and grading the UI
	// chrome (action bar/HP text/chat) along with the world would just make
	// native UI elements harder to read for no visual payoff; the world is
	// where the "does this even look like the same game" reaction actually
	// happens.
	public class CinematicGrade extends Module
	{
		// Tuned by eye, not measured against a reference — expect to need
		// live iteration once this is actually seen running against real
		// map art and character colors.
		private static const CONTRAST:Number   = 1.15; // >1 = more contrast
		private static const SATURATION:Number = 0.88; // <1 = slightly desaturated
		private static const WARM_R:Number     = 8;    // offset, brightens reds slightly
		private static const COOL_B:Number     = -6;   // offset, pulls blue down slightly

		private var _prevFilters:Array = null;
		private var _applied:Boolean   = false;

		public function CinematicGrade() { super("CinematicGrade"); }

		override public function onToggle(game:*):void
		{
			if (enabled) apply(game);
			else restore(game);
		}

		override public function onFrame(game:*):void
		{
			if (!enabled) return;
			// world gets torn down/rebuilt on map transitions — reapply if
			// our filter ever gets dropped off of it.
			try
			{
				if (!_applied || game.world.filters == null || game.world.filters.length == 0)
					apply(game);
			}
			catch (e:Error) {}
		}

		private function apply(game:*):void
		{
			try
			{
				if (!_applied) _prevFilters = game.world.filters;
				game.world.filters = [ new ColorMatrixFilter(buildMatrix()) ];
				_applied = true;
			}
			catch (e:Error) {}
		}

		private function restore(game:*):void
		{
			try { game.world.filters = _prevFilters; }
			catch (e:Error) {}
			_applied = false;
		}

		private function buildMatrix():Array
		{
			var sat:Array  = saturationMatrix(SATURATION);
			var con:Array  = contrastMatrix(CONTRAST);
			var tint:Array = tintMatrix(WARM_R, 0, COOL_B);
			return multiply(multiply(tint, con), sat);
		}

		// Luminance-preserving saturation — Adobe's standard weights.
		private function saturationMatrix(s:Number):Array
		{
			var lumR:Number = 0.3086, lumG:Number = 0.6094, lumB:Number = 0.0820;
			var sr:Number = (1 - s) * lumR;
			var sg:Number = (1 - s) * lumG;
			var sb:Number = (1 - s) * lumB;
			return [
				sr + s, sg,     sb,     0, 0,
				sr,     sg + s, sb,     0, 0,
				sr,     sg,     sb + s, 0, 0,
				0,      0,      0,      1, 0
			];
		}

		// Scales around the 128 midpoint so contrast changes don't also shift
		// overall brightness.
		private function contrastMatrix(c:Number):Array
		{
			var t:Number = 128 * (1 - c);
			return [
				c, 0, 0, 0, t,
				0, c, 0, 0, t,
				0, 0, c, 0, t,
				0, 0, 0, 1, 0
			];
		}

		private function tintMatrix(rOff:Number, gOff:Number, bOff:Number):Array
		{
			return [
				1, 0, 0, 0, rOff,
				0, 1, 0, 0, gOff,
				0, 0, 1, 0, bOff,
				0, 0, 0, 1, 0
			];
		}

		// Chains two 4x5 color matrices as if they were 5x5 homogeneous
		// matrices (implicit last row [0,0,0,0,1]) — this is what makes
		// applying matrix A then matrix B equivalent to a single combined
		// matrix, instead of needing two separate filter passes.
		private function multiply(a:Array, b:Array):Array
		{
			var am:Array = to5x5(a);
			var bm:Array = to5x5(b);
			var result:Array = [];
			for (var r:int = 0; r < 5; r++)
			{
				for (var c:int = 0; c < 5; c++)
				{
					var sum:Number = 0;
					for (var k:int = 0; k < 5; k++)
						sum += am[r * 5 + k] * bm[k * 5 + c];
					result.push(sum);
				}
			}
			// Drop the implicit last row — ColorMatrixFilter wants 4x5 (20 values).
			return result.slice(0, 20);
		}

		private function to5x5(m:Array):Array
		{
			var out:Array = m.concat();
			out.push(0, 0, 0, 0, 1);
			return out;
		}
	}
}
