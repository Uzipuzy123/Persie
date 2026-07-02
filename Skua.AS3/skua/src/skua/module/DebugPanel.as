package skua.module
{
	import flash.display.GradientType;
	import flash.display.Sprite;
	import flash.display.Stage;
	import flash.events.MouseEvent;
	import flash.geom.Matrix;
	import flash.text.TextField;
	import flash.text.TextFieldAutoSize;
	import flash.text.TextFieldType;
	import flash.text.TextFormat;

	public class DebugPanel extends Module
	{
		private static const W:int       = 540;
		private static const H:int       = 300;
		private static const TITLE_H:int = 18;
		private static const PAD:int     = 4;
		private static const BTN_W:int   = 46;
		private static const BTN_H:int   = 13;
		private static const GOLD:uint   = 0xC8A040;
		private static const GOLD2:uint  = 0x3D2808;

		// Static buffer — any module can call DebugPanel.log() / .append() / .clear()
		private static var _buffer:String = "";

		public static function log(text:String):void    { _buffer = text; }
		public static function append(text:String):void { _buffer += (_buffer.length > 0 ? "\n" : "") + text; }
		public static function clear():void             { _buffer = ""; }

		private static var _savedX:Number = -1e9;
		private static var _savedY:Number = -1e9;

		private var _overlay:Sprite;
		private var _tf:TextField;
		private var _stage:Stage;
		private var _dragHandle:Sprite;

		public function DebugPanel() { super("DebugPanel"); }

		override public function onToggle(game:*):void
		{
			if (enabled)
			{
				_overlay               = new Sprite();
				_overlay.mouseEnabled  = true;
				_overlay.mouseChildren = true;

				drawBg();

				// Invisible drag handle covering title area
				_dragHandle = new Sprite();
				_dragHandle.graphics.beginFill(0, 0.01);
				_dragHandle.graphics.drawRect(0, 0, W - BTN_W * 2 - 10, TITLE_H + 2);
				_dragHandle.graphics.endFill();
				_dragHandle.useHandCursor = true;
				_dragHandle.buttonMode    = true;
				_overlay.addChild(_dragHandle);
				_dragHandle.addEventListener(MouseEvent.MOUSE_DOWN, onDragStart);

				// Title
				var tlFmt:TextFormat = new TextFormat("Arial", 9, GOLD, true);
				var tlTf:TextField   = new TextField();
				tlTf.defaultTextFormat = tlFmt;
				tlTf.autoSize    = TextFieldAutoSize.LEFT;
				tlTf.selectable  = false;
				tlTf.mouseEnabled = false;
				tlTf.text = "DEBUG PANEL  —  select all: Ctrl+A  copy: Ctrl+C";
				tlTf.x    = PAD;
				tlTf.y    = int((TITLE_H - tlTf.height) * 0.5) + 1;
				_overlay.addChild(tlTf);

				// Clear button
				var clearBtn:Sprite = makeBtn("CLEAR", W - BTN_W - 3, 2);
				clearBtn.addEventListener(MouseEvent.MOUSE_UP, onClear);
				_overlay.addChild(clearBtn);

				// Selectable text field — the whole point: user can Ctrl+A → Ctrl+C
				var tfFmt:TextFormat = new TextFormat("Courier New", 9, 0xC8D8E8, false);
				_tf = new TextField();
				_tf.defaultTextFormat  = tfFmt;
				_tf.type               = TextFieldType.DYNAMIC;
				_tf.multiline          = true;
				_tf.wordWrap           = true;
				_tf.selectable         = true;
				_tf.mouseEnabled       = true;
				_tf.background         = true;
				_tf.backgroundColor    = 0x040810;
				_tf.border             = true;
				_tf.borderColor        = 0x1A2840;
				_tf.x                  = PAD;
				_tf.y                  = TITLE_H + PAD + 2;
				_tf.width              = W - PAD * 2;
				_tf.height             = H - TITLE_H - PAD * 3 - 2;
				_tf.text               = _buffer;
				_overlay.addChild(_tf);

				_tf.addEventListener(MouseEvent.MOUSE_WHEEL, onWheel);

				try
				{
					_stage = game.stage as Stage;
					_stage.addEventListener(MouseEvent.MOUSE_UP, onDragStop);

					if (_savedX > -1e8)
					{
						_overlay.x = _savedX;
						_overlay.y = _savedY;
					}
					else
					{
						_overlay.x = int((_stage.stageWidth  - W) * 0.5);
						_overlay.y = int((_stage.stageHeight - H) * 0.5);
					}
					_stage.addChild(_overlay);
				}
				catch (e:Error)
				{
					_overlay.x = 20;
					_overlay.y = 20;
					try { game.parent.addChild(_overlay); } catch (e2:Error) {}
				}
			}
			else
			{
				try
				{
					if (_dragHandle) _dragHandle.removeEventListener(MouseEvent.MOUSE_DOWN, onDragStart);
					if (_stage)      _stage.removeEventListener(MouseEvent.MOUSE_UP, onDragStop);
					if (_tf)         _tf.removeEventListener(MouseEvent.MOUSE_WHEEL, onWheel);
				}
				catch (e:Error) {}

				try { if (_overlay && _overlay.parent) _overlay.parent.removeChild(_overlay); }
				catch (e:Error) {}

				_savedX     = _overlay ? _overlay.x : _savedX;
				_savedY     = _overlay ? _overlay.y : _savedY;
				_overlay    = null;
				_tf         = null;
				_dragHandle = null;
				_stage      = null;
			}
		}

		override public function onFrame(game:*):void
		{
			if (_tf == null) return;
			if (_tf.text != _buffer)
			{
				_tf.text    = _buffer;
				_tf.scrollV = _tf.maxScrollV; // auto-scroll to bottom on new content
			}
		}

		private function onClear(e:MouseEvent):void  { _buffer = ""; }
		private function onDragStart(e:MouseEvent):void { _overlay.startDrag(); e.stopPropagation(); }
		private function onDragStop(e:MouseEvent):void
		{
			_overlay.stopDrag();
			if (_overlay) { _savedX = _overlay.x; _savedY = _overlay.y; }
		}
		private function onWheel(e:MouseEvent):void
		{
			if (!_tf) return;
			_tf.scrollV = Math.max(1, Math.min(_tf.maxScrollV, _tf.scrollV - e.delta));
			e.stopPropagation();
		}

		private function drawBg():void
		{
			var g:* = _overlay.graphics;
			var m:Matrix = new Matrix();

			m.createGradientBox(W, H, Math.PI * 0.5, 0, 0);
			g.beginGradientFill(GradientType.LINEAR, [0x9A7230, 0x3D2808], [1, 1], [0, 255], m);
			g.drawRoundRect(0, 0, W, H, 5, 5);
			g.endFill();

			m.createGradientBox(W-4, H-4, Math.PI * 0.5, 2, 2);
			g.beginGradientFill(GradientType.LINEAR, [0x0D1E36, 0x060A14], [0.97, 0.97], [0, 255], m);
			g.drawRoundRect(2, 2, W-4, H-4, 4, 4);
			g.endFill();

			g.lineStyle(1, GOLD, 0.38);
			g.drawRoundRect(2, 2, W-4, H-4, 4, 4);

			m.createGradientBox(W-6, TITLE_H + 2, Math.PI * 0.5, 3, 3);
			g.beginGradientFill(GradientType.LINEAR, [0x1C3050, 0x0A1628], [0.95, 0.95], [0, 255], m);
			g.drawRect(3, 3, W-6, TITLE_H + 2);
			g.endFill();

			g.lineStyle(1, GOLD, 0.22);
			g.moveTo(3, TITLE_H + 4);
			g.lineTo(W - 3, TITLE_H + 4);
		}

		private function makeBtn(label:String, bx:int, by:int):Sprite
		{
			var sp:Sprite = new Sprite();
			sp.graphics.beginFill(GOLD2, 0.85);
			sp.graphics.drawRoundRect(0, 0, BTN_W, BTN_H, 3, 3);
			sp.graphics.endFill();
			sp.graphics.lineStyle(1, GOLD, 0.7);
			sp.graphics.drawRoundRect(0, 0, BTN_W, BTN_H, 3, 3);

			var fmt:TextFormat = new TextFormat("Arial", 8, GOLD, true);
			var tf:TextField   = new TextField();
			tf.defaultTextFormat = fmt;
			tf.autoSize     = TextFieldAutoSize.LEFT;
			tf.selectable   = false;
			tf.mouseEnabled = false;
			tf.text = label;
			tf.x    = int((BTN_W - tf.width)  * 0.5);
			tf.y    = int((BTN_H - tf.height) * 0.5);
			sp.addChild(tf);

			sp.x = bx; sp.y = by;
			sp.useHandCursor = true;
			sp.buttonMode    = true;
			return sp;
		}
	}
}
