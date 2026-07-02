package skua.module
{
	import flash.display.Graphics;
	import flash.display.Shape;
	import flash.display.Sprite;
	import flash.display.Stage;
	import flash.events.MouseEvent;
	import flash.text.TextField;
	import flash.text.TextFieldAutoSize;
	import flash.text.TextFormat;

	public class SkuaSettingsButton extends Module
	{
		private static const BTN_R:int    = 18;
		private static const PANEL_W:int  = 168;
		private static const ROW_H:int    = 26;
		private static const DOT_R:int    = 4;

		private static const COL_ON:uint  = 0x23A55A;
		private static const COL_OFF:uint = 0x3A3A3A;

		// Which modules appear in the panel, in order
		private static const ROWS:Array = [
			{ name:"MiniMap",          label:"Mini Map"        },
			{ name:"KillFeed",         label:"Kill Feed"       },
			{ name:"ScoreboardOverlay",label:"Scoreboard"      },
			{ name:"HighlightEnemies", label:"Highlight"       },
			{ name:"EnemyHPOverlay",   label:"HP Overlay"      },
			{ name:"HideRoomNumber",   label:"Hide Room #"     },
			{ name:"DisableShadows",   label:"No Shadows"      },
			{ name:"MuteGame",         label:"Mute Audio"      },
		];

		private var _stage:Stage;
		private var _btn:Sprite;
		private var _panel:Sprite;
		private var _open:Boolean = false;

		public function SkuaSettingsButton() { super("SkuaSettingsButton"); }

		override public function onToggle(game:*):void
		{
			if (!enabled) cleanup();
			// creation deferred to first onFrame so stage is guaranteed ready
		}

		override public function onFrame(game:*):void
		{
			if (!enabled) return;
			if (!_btn)
			{
				// Lazy-create on first frame after enable
				try { _stage = game.stage as Stage; } catch (e:Error) { return; }
				if (!_stage) return;
				_btn   = buildBtn();
				_panel = buildPanel();
				_stage.addChild(_btn);
				_stage.addChild(_panel);
			}
			reposition();
		}

		// ── positioning ──────────────────────────────────────────────────────
		private function reposition():void
		{
			if (!_stage || !_btn) return;
			// Sit over the inventory bag button — bottom-right corner
			_btn.x = Math.round(_stage.stageWidth  - 17);
			_btn.y = Math.round(_stage.stageHeight - 31);

			// Panel opens above and to the left (we're in the corner)
			_panel.x = _btn.x - PANEL_W + BTN_R;
			_panel.y = _btn.y - BTN_R - _panel.height - 6;
		}

		// ── button ───────────────────────────────────────────────────────────
		private function buildBtn():Sprite
		{
			var sp:Sprite    = new Sprite();
			var g:Graphics   = sp.graphics;
			var logoR:Number = BTN_R - 2;   // half-size of the squircle
			var cr:Number    = logoR * 0.45; // corner radius — matches AQW icon shape

			// Invisible hit area
			g.beginFill(0x000000, 0);
			g.drawCircle(0, 0, BTN_R);
			g.endFill();

			// Thin dark shadow/border underneath
			g.beginFill(0x111111, 0.7);
			g.drawRoundRect(-logoR - 1, -logoR - 1, (logoR + 1) * 2, (logoR + 1) * 2, cr + 1, cr + 1);
			g.endFill();

			// ── Left half: gray (full squircle, right will be covered by blue) ──
			g.beginFill(0xD0D0D0, 1);
			g.drawRoundRect(-logoR, -logoR, logoR * 2, logoR * 2, cr, cr);
			g.endFill();

			// ── Right half: blue squircle masked to right side ───────────────────
			var blueSprite:Sprite = new Sprite();
			blueSprite.graphics.beginFill(0x4499EE, 1);
			blueSprite.graphics.drawRoundRect(-logoR, -logoR, logoR * 2, logoR * 2, cr, cr);
			blueSprite.graphics.endFill();

			var blueMask:Shape = new Shape();
			blueMask.graphics.beginFill(0xFF0000, 1);
			blueMask.graphics.drawRect(0, -logoR - 2, logoR + 2, logoR * 2 + 4);
			blueMask.graphics.endFill();

			blueSprite.mask = blueMask;
			sp.addChild(blueSprite);
			sp.addChild(blueMask);

			// ── "PVP" text on top ─────────────────────────────────────────────────
			var fmt:TextFormat = new TextFormat("Arial", 6, 0x111111, true);
			var tf:TextField   = new TextField();
			tf.defaultTextFormat = fmt;
			tf.autoSize     = TextFieldAutoSize.LEFT;
			tf.selectable   = false;
			tf.mouseEnabled = false;
			tf.text = "PVP";
			tf.x = -int(tf.width  * 0.5);
			tf.y = -int(tf.height * 0.5) - 1;
			sp.addChild(tf);

			sp.useHandCursor = true;
			sp.buttonMode    = true;
			sp.addEventListener(MouseEvent.CLICK,      onBtnClick);
			sp.addEventListener(MouseEvent.MOUSE_OVER, onBtnOver);
			sp.addEventListener(MouseEvent.MOUSE_OUT,  onBtnOut);
			return sp;
		}

		private function onBtnOver(e:MouseEvent):void
		{
			if (!_btn) return;
			// Lighten slightly
			_btn.alpha = 1.2;
		}
		private function onBtnOut(e:MouseEvent):void
		{
			if (!_btn) return;
			_btn.alpha = 1.0;
		}
		private function onBtnClick(e:MouseEvent):void
		{
			e.stopPropagation();
			_open         = !_open;
			_panel.visible = _open;
			if (_open) refreshDots();
		}

		// ── panel ────────────────────────────────────────────────────────────
		private function buildPanel():Sprite
		{
			var sp:Sprite   = new Sprite();
			var panH:int    = ROWS.length * ROW_H + 10;
			var g:Graphics  = sp.graphics;

			// Background
			g.lineStyle(1, 0x666666, 0.85);
			g.beginFill(0x181818, 0.96);
			g.drawRoundRect(0, 0, PANEL_W, panH, 6, 6);
			g.endFill();

			// Header accent line
			g.lineStyle(0);
			g.beginFill(0x23A55A, 0.6);
			g.drawRoundRect(0, 0, PANEL_W, 3, 3, 3);
			g.endFill();

			for (var i:int = 0; i < ROWS.length; i++)
				sp.addChild(buildRow(i, String(ROWS[i].name), String(ROWS[i].label)));

			sp.visible = false;
			return sp;
		}

		private function buildRow(idx:int, modName:String, label:String):Sprite
		{
			var sp:Sprite  = new Sprite();
			var g:Graphics = sp.graphics;
			sp.y = 5 + idx * ROW_H;
			sp.name = modName;

			// Hover background (transparent by default)
			var bg:Shape = new Shape();
			bg.name = "bg";
			bg.graphics.beginFill(0xFFFFFF, 0);
			bg.graphics.drawRect(0, 0, PANEL_W, ROW_H);
			bg.graphics.endFill();
			sp.addChild(bg);

			// Divider (except first row)
			if (idx > 0)
			{
				var div:Shape = new Shape();
				div.graphics.lineStyle(1, 0x333333, 0.8);
				div.graphics.moveTo(8,  0);
				div.graphics.lineTo(PANEL_W - 8, 0);
				sp.addChild(div);
			}

			// Label
			var fmt:TextFormat = new TextFormat("Arial", 11, 0xC8C8C8);
			var tf:TextField   = new TextField();
			tf.defaultTextFormat = fmt;
			tf.autoSize     = TextFieldAutoSize.LEFT;
			tf.selectable   = false;
			tf.mouseEnabled = false;
			tf.text = label;
			tf.x    = 10;
			tf.y    = int((ROW_H - tf.height) * 0.5);
			sp.addChild(tf);

			// Status dot
			var dot:Shape = new Shape();
			dot.name = "dot";
			var mod:Module = Modules.getModule(modName);
			drawDot(dot, mod ? mod.enabled : false);
			dot.x = PANEL_W - 14;
			dot.y = int(ROW_H * 0.5);
			sp.addChild(dot);

			sp.useHandCursor = true;
			sp.buttonMode    = true;
			sp.addEventListener(MouseEvent.CLICK,      onRowClick);
			sp.addEventListener(MouseEvent.MOUSE_OVER, onRowOver);
			sp.addEventListener(MouseEvent.MOUSE_OUT,  onRowOut);
			return sp;
		}

		private function drawDot(dot:Shape, on:Boolean):void
		{
			dot.graphics.clear();
			dot.graphics.beginFill(on ? COL_ON : COL_OFF, 1);
			dot.graphics.drawCircle(0, 0, DOT_R);
			dot.graphics.endFill();
		}

		private function onRowOver(e:MouseEvent):void
		{
			var row:Sprite = e.currentTarget as Sprite;
			var bg:Shape   = row.getChildByName("bg") as Shape;
			if (!bg) return;
			bg.graphics.clear();
			bg.graphics.beginFill(0xFFFFFF, 0.07);
			bg.graphics.drawRect(0, 0, PANEL_W, ROW_H);
			bg.graphics.endFill();
		}
		private function onRowOut(e:MouseEvent):void
		{
			var row:Sprite = e.currentTarget as Sprite;
			var bg:Shape   = row.getChildByName("bg") as Shape;
			if (!bg) return;
			bg.graphics.clear();
			bg.graphics.beginFill(0xFFFFFF, 0);
			bg.graphics.drawRect(0, 0, PANEL_W, ROW_H);
			bg.graphics.endFill();
		}
		private function onRowClick(e:MouseEvent):void
		{
			e.stopPropagation();
			var modName:String = Sprite(e.currentTarget).name;
			var mod:Module = Modules.getModule(modName);
			if (!mod) return;
			if (mod.enabled) Modules.disable(modName);
			else             Modules.enable(modName);
			refreshDots();
		}

		private function refreshDots():void
		{
			if (!_panel) return;
			for (var i:int = 0; i < _panel.numChildren; i++)
			{
				var row:Sprite = _panel.getChildAt(i) as Sprite;
				if (!row) continue;
				var mod:Module = Modules.getModule(row.name);
				if (!mod) continue;
				var dot:Shape = row.getChildByName("dot") as Shape;
				if (dot) drawDot(dot, mod.enabled);
			}
		}

		// ── cleanup ──────────────────────────────────────────────────────────
		private function cleanup():void
		{
			try
			{
				if (_btn)
				{
					_btn.removeEventListener(MouseEvent.CLICK,      onBtnClick);
					_btn.removeEventListener(MouseEvent.MOUSE_OVER, onBtnOver);
					_btn.removeEventListener(MouseEvent.MOUSE_OUT,  onBtnOut);
					if (_btn.parent) _btn.parent.removeChild(_btn);
				}
				if (_panel && _panel.parent) _panel.parent.removeChild(_panel);
			}
			catch (e:Error) {}
			_btn   = null;
			_panel = null;
			_stage = null;
			_open  = false;
		}
	}
}
