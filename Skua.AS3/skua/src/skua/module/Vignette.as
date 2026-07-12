package skua.module
{
	import flash.display.GradientType;
	import flash.display.Sprite;
	import flash.geom.Matrix;

	public class Vignette extends Module
	{
		private var _shape:Sprite     = null;
		private var _style:int        = 0;
		private var _animated:Boolean = false;
		private var _phase:Number     = 0;
		private var _pulseFreq:Number = 0;

		// [colorHex, edgeAlpha, innerStop(0-255), animated, pulseFreq]
		private static const STYLES:Array = [
			[0x000000, 0.68, 110, false, 0.00], // 1: Classic Shadow
			[0x000000, 0.88,  80, false, 0.00], // 2: Heavy Black
			[0x220000, 0.75, 100, false, 0.00], // 3: Blood Red
			[0x000022, 0.70, 105, false, 0.00], // 4: Cold Blue
			[0x100018, 0.72, 100, false, 0.00], // 5: Mystic Purple
			[0x1A1200, 0.65, 115, false, 0.00], // 6: Warm Gold
			[0x001500, 0.68, 108, false, 0.00], // 7: Forest Green
			[0x001818, 0.62, 112, false, 0.00], // 8: Teal Mist
			[0x000000, 0.82,  90, true,  0.07], // 9: Pulse Dark
			[0x200000, 0.78,  95, true,  0.09], // 10: Pulse Red
			[0x000000, 0.38, 130, false, 0.00], // 11: Soft Fade
		];

		public function Vignette() { super("Vignette"); }

		public function setStyle(n:int):void
		{
			_style = n;
			remove();
		}

		override public function onToggle(game:*):void
		{
			if (enabled) { _phase = 0; attach(game); }
			else remove();
		}

		override public function onFrame(game:*):void
		{
			if (_shape == null || _shape.parent == null) attach(game);
			if (_animated && _shape != null)
			{
				_phase += _pulseFreq;
				_shape.alpha = 0.65 + 0.35 * Math.sin(_phase);
			}
		}

		private function attach(game:*):void
		{
			remove();
			if (_style < 1 || _style > STYLES.length) return;
			var sd:Array     = STYLES[_style - 1];
			var col:uint     = uint(sd[0]);
			var edgeA:Number = Number(sd[1]);
			var inner:int    = int(sd[2]);
			_animated        = Boolean(sd[3]);
			_pulseFreq       = Number(sd[4]);

			var sw:Number = 800, sh:Number = 600;
			try { sw = game.stage.stageWidth; sh = game.stage.stageHeight; } catch (e:Error) {}

			_shape = new Sprite();
			_shape.mouseEnabled  = false;
			_shape.mouseChildren = false;

			var m:Matrix = new Matrix();
			m.createGradientBox(sw, sh, 0, 0, 0);

			_shape.graphics.beginGradientFill(
				GradientType.RADIAL,
				[col, col],
				[0, edgeA],
				[inner, 255],
				m
			);
			_shape.graphics.drawRect(0, 0, sw, sh);
			_shape.graphics.endFill();

			try { game.stage.addChild(_shape); }
			catch (e:Error) { try { game.parent.addChild(_shape); } catch (e2:Error) {} }
		}

		private function remove():void
		{
			if (_shape != null)
			{
				try { _shape.parent.removeChild(_shape); } catch (e:Error) {}
				_shape = null;
			}
		}
	}
}
