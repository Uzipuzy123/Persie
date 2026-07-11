package skua.module
{
	import flash.display.Sprite;
	import flash.display.Shape;
	import flash.events.MouseEvent;
	import flash.events.KeyboardEvent;
	import flash.text.TextField;
	import flash.text.TextFormat;
	import flash.text.TextFieldAutoSize;
	import flash.ui.Keyboard;
	import flash.external.ExternalInterface;

	/**
	 * Clickable in-game settings menu — the AS3-native equivalent of the WPF
	 * HudWindow/QualityWindow/ScoreboardWindow pickers/toggles. Two kinds of
	 * tab, distinguished by `kind`:
	 *
	 *  - "style": select-one-of-N rows calling Modules.getModule(name).setXXX(id).
	 *    Most tabs are this. PlayerHPBars is a special case within this kind —
	 *    it has no dedicated "off" style id (id 0 is a real style, "LoL"), so
	 *    its options list uses a sentinel id of -1 for "Off", which calls
	 *    Modules.disable() instead of setStyle(); any other id calls
	 *    Modules.enable() (needsEnable:true) then setStyle(id).
	 *
	 *  - "toggle": plain on/off rows mapping straight to Modules.enable(name)/
	 *    disable(name) — reads the module's real `enabled` field each render
	 *    rather than tracking state locally, so it can never drift out of
	 *    sync with what's actually active.
	 *
	 * Ctrl+M toggles the panel. No host application involved — everything
	 * here calls straight into the same AS3 module methods Main.as's
	 * ExternalInterface callbacks already wrap.
	 */
	public class IngameMenu extends Module
	{
		// ── layout ────────────────────────────────────────────────────────────
		private static const TITLE_H:Number   = 30;
		private static const SIDEBAR_W:Number = 150;
		private static const CONTENT_W:Number = 260;
		private static const ROW_H:Number     = 27;
		private static const SLIDER_ROW_H:Number = 40;
		private static const TAB_ITEM_H:Number = 24;
		private static const SECTION_H:Number  = 22;
		private static const OFF_ID:int = -1;

		// ── palette ───────────────────────────────────────────────────────────
		private static const COL_BG:uint       = 0x14161C;
		private static const COL_SIDEBAR:uint  = 0x191C23;
		private static const COL_BORDER:uint   = 0x33384A;
		private static const COL_ROW:uint      = 0x1E212B;
		private static const COL_ROW_HOVER:uint = 0x272C39;
		private static const COL_ROW_ACTIVE:uint = 0x2A2410;
		private static const COL_TEXT:uint     = 0xDCE0E8;
		private static const COL_MUTED:uint    = 0x7A8091;
		private static const COL_GOLD:uint     = 0xD9AE52;
		private static const COL_GREEN:uint    = 0x2FBF71;
		private static const COL_OFF:uint      = 0x565C6B;

		private var _game:*;
		private var _panel:Sprite;
		private var _titleBar:Sprite;
		private var _sidebar:Sprite;
		private var _content:Sprite;
		private var _tabs:Array;
		private var _activeTab:int = 0;

		public function IngameMenu() { super("IngameMenu"); }

		override public function onToggle(game:*):void
		{
			_game = game;
			if (enabled)
			{
				game.stage.addEventListener(KeyboardEvent.KEY_UP, onKeyUp);
				if (_tabs == null) buildTabDefs();
			}
			else
			{
				game.stage.removeEventListener(KeyboardEvent.KEY_UP, onKeyUp);
			}
		}

		private function onKeyUp(e:KeyboardEvent):void
		{
			try
			{
				if (e.ctrlKey && e.keyCode == Keyboard.M)
					toggleMenu();
			}
			catch (err:Error) {}
		}

		// Temporary diagnostic aid — routes through the same ExternalInterface
		// pipe Externalizer.debug() already uses, so it shows up in the C#
		// host's console without needing a Flash debugger attached.
		private function debug(message:String):void
		{
			try { ExternalInterface.call("debug", "[IngameMenu] " + message); }
			catch (err:Error) {}
		}

		// ── tab/option definitions ───────────────────────────────────────────

		private function buildTabDefs():void
		{
			_tabs = [];

			addSection("STYLES");

			addTab("HUD", "SelfHud", "setStyle", [
				{id:0,label:"Default"},{id:1,label:"Sleek Gradient"},{id:2,label:"Tactical"},
				{id:3,label:"Neon"},{id:4,label:"Ornate"},{id:5,label:"Hex Plate"},
				{id:6,label:"Liquid"},{id:7,label:"Angular"},{id:8,label:"Gothic Blood"},{id:9,label:"Orb"}
			]);

			addTab("Skill Bar", "SkillBarSkin", "setStyle", [
				{id:0,label:"Default"},{id:1,label:"Hex Grid"}
			]);

			addTab("Blue Flag", "TeamFlagReskin", "setBlueStyle", [
				{id:0,label:"Default"},{id:1,label:"Rising Sun"},{id:2,label:"Shuriken"},
				{id:3,label:"Sakura"},{id:4,label:"Lightning Bolt"},{id:5,label:"Crescent Moon"},{id:6,label:"Katana"}
			]);

			addTab("Red Flag", "TeamFlagReskin", "setRedStyle", [
				{id:0,label:"Default"},{id:1,label:"Flame"},{id:2,label:"Oni Eye"},
				{id:3,label:"Demon Horns"},{id:4,label:"Claw Marks"},{id:5,label:"Blood Drop"},{id:6,label:"Phoenix Wing"}
			]);

			addTab("Scoreboard", "ScoreboardSkin", "setSkin", [
				{id:0,label:"Default"},{id:1,label:"Esports"},{id:2,label:"Neon Bar"},{id:3,label:"Radial"},
				{id:4,label:"Orb"},{id:5,label:"Dial"},{id:6,label:"Hex"},{id:7,label:"Diamond"}
			]);

			addTab("Nameplate", "NameplateFont", "setFont", [
				{id:0,label:"Default"},{id:1,label:"Comic Sans"},{id:2,label:"Impact"},{id:3,label:"Papyrus"},
				{id:4,label:"Arial Black"},{id:5,label:"Consolas"},{id:6,label:"Segoe Script"},{id:7,label:"Gabriola"},
				{id:8,label:"MV Boli"},{id:9,label:"Bahnschrift"},{id:10,label:"Ink Free"},{id:11,label:"Golden Royalty"},
				{id:12,label:"Ancient Blood"},{id:13,label:"Toxic Glow"},{id:14,label:"Frostbite"},{id:15,label:"Cyber Pink"}
			]);

			addTab("Self Outline", "SelfOutline", "setColor", [
				{id:0,label:"Off"},{id:1,label:"Cyan"},{id:2,label:"White"},{id:3,label:"Gold"},{id:4,label:"Green"},
				{id:5,label:"Red"},{id:6,label:"Blue"},{id:7,label:"Purple"},{id:8,label:"Pink"}
			]);

			addTab("Enemy Outline", "EnemyOutline", "setColor", [
				{id:0,label:"Off"},{id:1,label:"Red"},{id:2,label:"Orange"},{id:3,label:"White"},{id:4,label:"Gold"},
				{id:5,label:"Purple"},{id:6,label:"Magenta"},{id:7,label:"Green"},{id:8,label:"Cyan"}
			]);

			addTab("My Hit Style", "HitFlash", "setMyStyle", hitStyleOptions());
			addTab("Enemy Hit Style", "HitFlash", "setEnemyStyle", hitStyleOptions());

			addTab("Vignette", "Vignette", "setStyle", [
				{id:0,label:"Off"},{id:1,label:"Classic Shadow"},{id:2,label:"Heavy Black"},{id:3,label:"Blood Red"},
				{id:4,label:"Cold Blue"},{id:5,label:"Mystic Purple"},{id:6,label:"Warm Gold"},{id:7,label:"Forest Green"},
				{id:8,label:"Teal Mist"},{id:9,label:"Pulse Dark"},{id:10,label:"Pulse Red"},{id:11,label:"Soft Fade"}
			]);

			addTab("Kill Flash Screen", "KillFlash", "setScreenStyle", [
				{id:0,label:"Off"},{id:1,label:"White Flash"},{id:2,label:"Red Rush"},{id:3,label:"Gold Strike"},
				{id:4,label:"Blue Freeze"},{id:5,label:"Purple Hex"},{id:6,label:"Green Vengeance"},{id:7,label:"Pink Burst"},
				{id:8,label:"Teal Wave"},{id:9,label:"Double White"},{id:10,label:"Double Red"},{id:11,label:"Orange Fury"}
			]);

			addTab("Kill Flash Player", "KillFlash", "setPlayerStyle", [
				{id:0,label:"Off"},{id:1,label:"Bleach White"},{id:2,label:"Blood Splatter"},{id:3,label:"Gold Victory"},
				{id:4,label:"Ice Blue"},{id:5,label:"Ghost"},{id:6,label:"Purple Curse"},{id:7,label:"Orange Burn"},
				{id:8,label:"Void Black"},{id:9,label:"Electric Pink"}
			]);

			// PlayerHPBars has no dedicated "off" style id — id 0 is a real
			// style (LoL). OFF_ID is a sentinel this file interprets specially
			// (Modules.disable instead of setStyle); needsEnable:true means
			// every other row calls Modules.enable() first, since the module
			// starts disabled and setStyle() alone wouldn't make it render.
			addTab("HP Bar", "PlayerHPBars", "setStyle", [
				{id:OFF_ID,label:"Off"},
				{id:0,label:"LoL"},{id:1,label:"WoW"},{id:2,label:"Fortnite"},{id:3,label:"Valorant"},
				{id:4,label:"Rune"},{id:5,label:"Overwatch"},{id:6,label:"Elden Ring"},{id:7,label:"GTA"},
				{id:8,label:"Minecraft"},{id:9,label:"Neon Glow"},{id:10,label:"Gradient"},
				{id:11,label:"Pixel Blocks"},{id:12,label:"AQW Gold"}
			], true, OFF_ID, [
				{ label:"Size", moduleName:"PlayerHPBars", setterName:"setScale",
				  min:10, max:100, value:60, step:5, unit:"%", needsEnable:true }
			]);

			addSection("TOGGLES");

			addToggleTab("Performance", [
				{name:"ClearFilters", label:"Clear Filters"},
				{name:"StopAnimations", label:"Freeze BG"},
				{name:"KillParticles", label:"Kill Particles"},
				{name:"OptimizeMap", label:"Optimize Map"},
				{name:"MuteGame", label:"Mute Audio"},
				{name:"DisableShadows", label:"Disable Shadows"},
				{name:"HighlightEnemies", label:"Highlight Enemies"}
			]);

			addSliderOnlyTab("FPS Limiter", [
				{ label:"Frame Rate", moduleName:"FpsControl", setterName:"setFps",
				  min:24, max:60, value:30, step:1, unit:" FPS", needsEnable:false }
			]);

			addToggleTab("Overlays", [
				{name:"MiniMap", label:"Mini Map"},
				{name:"KillFeed", label:"Kill Feed"},
				{name:"EnemyHPOverlay", label:"HP Overlay"},
				{name:"ScoreboardOverlay", label:"Scoreboard"},
				{name:"DebugPanel", label:"Debug Panel"},
				{name:"SkuaSettingsButton", label:"Ingame Button"},
				{name:"FastDoorEnter", label:"Fast Door Enter"},
				{name:"MapSkin", label:"Bludrutbrawl Skin"},
				{name:"YulgarSkin", label:"Yulgar Skin (Max Quality)"},
				{name:"MapDebug", label:"Map Debug"}
			]);

			addToggleTab("Effects", [
				{name:"PortalFlash", label:"Portal Flash"},
				{name:"RespawnEffect", label:"Respawn Effect"},
				{name:"DisableNativeGlow", label:"Disable All Glow"},
				{name:"DisableNativeAnimation", label:"Disable All Animation"},
				{name:"LowHPFlash", label:"Low HP Flash"},
				{name:"RevengeKill", label:"Revenge Kill"},
				{name:"KillStreakAnnouncer", label:"Kill Streak Announcer"}
			]);

			// First real (non-section) entry starts active.
			for (var i:int = 0; i < _tabs.length; i++)
			{
				if (_tabs[i].kind != "section") { _activeTab = i; break; }
			}
		}

		private function hitStyleOptions():Array
		{
			return [
				{id:0,label:"Off"},{id:1,label:"White"},{id:2,label:"Red"},{id:3,label:"Orange"},{id:4,label:"Blue"},
				{id:5,label:"Green"},{id:6,label:"Purple"},{id:7,label:"Pink"},{id:8,label:"Yellow"},{id:9,label:"Cyan"}
			];
		}

		private function addSection(label:String):void
		{
			_tabs.push({ kind:"section", label:label });
		}

		private function addTab(label:String, moduleName:String, setterName:String, options:Array, needsEnable:Boolean = false, defaultId:int = 0, sliders:Array = null):void
		{
			_tabs.push({ kind:"style", label:label, moduleName:moduleName, setterName:setterName,
				options:options, current:defaultId, needsEnable:needsEnable, sliders:sliders });
		}

		private function addToggleTab(label:String, items:Array):void
		{
			_tabs.push({ kind:"toggle", label:label, items:items });
		}

		private function addSliderOnlyTab(label:String, sliders:Array):void
		{
			_tabs.push({ kind:"slider", label:label, sliders:sliders });
		}

		// ── panel construction ───────────────────────────────────────────────

		private function toggleMenu():void
		{
			if (_panel && _panel.parent)
			{
				_game.stage.removeEventListener(MouseEvent.MOUSE_UP, onDragStop);
				_panel.parent.removeChild(_panel);
				_panel = null;
				return;
			}
			buildPanel();
		}

		private function buildPanel():void
		{
			var sidebarHeight:Number = sidebarContentHeight();
			var panelH:Number = TITLE_H + sidebarHeight;

			_panel = new Sprite();
			_panel.x = 200;
			_panel.y = 40;

			var frame:Shape = new Shape();
			frame.graphics.beginFill(COL_BG, 1);
			frame.graphics.lineStyle(1, COL_BORDER);
			frame.graphics.drawRoundRect(0, 0, SIDEBAR_W + CONTENT_W, panelH, 8, 8);
			frame.graphics.endFill();
			_panel.addChild(frame);

			buildTitleBar();

			_sidebar = new Sprite();
			_sidebar.y = TITLE_H;
			_panel.addChild(_sidebar);

			_content = new Sprite();
			_content.x = SIDEBAR_W;
			_content.y = TITLE_H;
			_panel.addChild(_content);

			buildSidebar();
			showTab(_activeTab);

			_game.stage.addChild(_panel);
		}

		private function sidebarContentHeight():Number
		{
			var h:Number = 6;
			for each (var t:Object in _tabs)
				h += (t.kind == "section") ? SECTION_H : TAB_ITEM_H;
			return Math.max(h, 200);
		}

		// ── title bar: drag handle + close button ───────────────────────────

		private function buildTitleBar():void
		{
			_titleBar = new Sprite();
			_titleBar.buttonMode = true;

			var bg:Shape = new Shape();
			bg.graphics.beginFill(0x1A1D24, 1);
			bg.graphics.drawRoundRectComplex(0, 0, SIDEBAR_W + CONTENT_W, TITLE_H, 8, 8, 0, 0);
			bg.graphics.endFill();
			bg.graphics.lineStyle(1, COL_GOLD, 0.5);
			bg.graphics.moveTo(0, TITLE_H - 0.5);
			bg.graphics.lineTo(SIDEBAR_W + CONTENT_W, TITLE_H - 0.5);
			_titleBar.addChild(bg);

			var title:TextField = new TextField();
			title.autoSize = TextFieldAutoSize.LEFT;
			title.selectable = false;
			title.mouseEnabled = false;
			title.defaultTextFormat = new TextFormat("Georgia", 13, COL_GOLD, false, true);
			title.text = "GUNLIVE TEST";
			title.x = 12; title.y = 6;
			_titleBar.addChild(title);

			var close:Sprite = buildCloseButton();
			close.x = SIDEBAR_W + CONTENT_W - 24;
			close.y = 6;
			_titleBar.addChild(close);

			_titleBar.addEventListener(MouseEvent.MOUSE_DOWN, onDragStart);
			_panel.addChild(_titleBar);
		}

		private function buildCloseButton():Sprite
		{
			var btn:Sprite = new Sprite();
			btn.buttonMode = true;

			var bg:Shape = new Shape();
			bg.graphics.beginFill(0xB33A3A, 1);
			bg.graphics.drawCircle(9, 9, 9);
			bg.graphics.endFill();
			btn.addChild(bg);

			var x:TextField = new TextField();
			x.autoSize = TextFieldAutoSize.CENTER;
			x.selectable = false;
			x.mouseEnabled = false;
			x.defaultTextFormat = new TextFormat("Arial", 10, 0xFFFFFF, true);
			x.text = "✕";
			x.x = 9 - x.textWidth / 2 - 2;
			x.y = 9 - x.textHeight / 2 - 1;
			btn.addChild(x);

			btn.addEventListener(MouseEvent.CLICK, function (e:MouseEvent):void { toggleMenu(); });
			return btn;
		}

		private function onDragStart(e:MouseEvent):void
		{
			_panel.startDrag();
			_game.stage.addEventListener(MouseEvent.MOUSE_UP, onDragStop);
		}

		private function onDragStop(e:MouseEvent):void
		{
			if (_panel) _panel.stopDrag();
			_game.stage.removeEventListener(MouseEvent.MOUSE_UP, onDragStop);
		}

		// ── sidebar ───────────────────────────────────────────────────────────

		private function buildSidebar():void
		{
			while (_sidebar.numChildren > 0) _sidebar.removeChildAt(0);

			var bg:Shape = new Shape();
			bg.graphics.beginFill(COL_SIDEBAR, 1);
			bg.graphics.drawRect(0, 0, SIDEBAR_W, sidebarContentHeight());
			bg.graphics.endFill();
			_sidebar.addChild(bg);

			var y:Number = 6;
			for (var i:int = 0; i < _tabs.length; i++)
			{
				var t:Object = _tabs[i];
				if (t.kind == "section")
				{
					addSectionLabel(t.label, y);
					y += SECTION_H;
				}
				else
				{
					addSidebarItem(t, i, y);
					y += TAB_ITEM_H;
				}
			}
		}

		private function addSectionLabel(label:String, y:Number):void
		{
			var tf:TextField = new TextField();
			tf.autoSize = TextFieldAutoSize.LEFT;
			tf.selectable = false;
			tf.mouseEnabled = false;
			tf.defaultTextFormat = new TextFormat("Consolas", 8, COL_MUTED, true);
			tf.text = "─ " + label;
			tf.x = 12; tf.y = y + 5;
			_sidebar.addChild(tf);
		}

		// Separate function call per item (like addRow already does for rows)
		// so each click closure captures its OWN idx/t — see the historical
		// note on this same bug in the previous version of buildTabsBar().
		private function addSidebarItem(t:Object, idx:int, y:Number):void
		{
			var isActive:Boolean = (idx == _activeTab);

			var item:Sprite = new Sprite();
			item.buttonMode = true;
			item.y = y;

			var bg:Shape = new Shape();
			bg.graphics.beginFill(isActive ? 0x241F14 : COL_SIDEBAR, 1);
			bg.graphics.drawRect(0, 0, SIDEBAR_W, TAB_ITEM_H);
			bg.graphics.endFill();
			if (isActive)
			{
				bg.graphics.beginFill(COL_GOLD, 1);
				bg.graphics.drawRect(0, 0, 3, TAB_ITEM_H);
				bg.graphics.endFill();
			}
			item.addChild(bg);

			var tf:TextField = new TextField();
			tf.autoSize = TextFieldAutoSize.LEFT;
			tf.selectable = false;
			tf.mouseEnabled = false;
			tf.defaultTextFormat = new TextFormat("Arial", 10.5, isActive ? 0xFFFFFF : COL_MUTED, isActive);
			tf.text = t.label;
			tf.x = 14; tf.y = 5;
			item.addChild(tf);

			item.addEventListener(MouseEvent.MOUSE_OVER, function (e:MouseEvent):void
			{
				if (idx != _activeTab) bg.graphics.beginFill(0x20242D, 1), bg.graphics.drawRect(0, 0, SIDEBAR_W, TAB_ITEM_H), bg.graphics.endFill();
			});
			item.addEventListener(MouseEvent.MOUSE_OUT, function (e:MouseEvent):void
			{
				if (idx != _activeTab) { bg.graphics.clear(); bg.graphics.beginFill(COL_SIDEBAR, 1); bg.graphics.drawRect(0, 0, SIDEBAR_W, TAB_ITEM_H); bg.graphics.endFill(); }
			});
			item.addEventListener(MouseEvent.CLICK, function (e:MouseEvent):void
			{
				_activeTab = idx;
				buildSidebar();
				showTab(_activeTab);
			});

			_sidebar.addChild(item);
		}

		// ── content ───────────────────────────────────────────────────────────

		private function showTab(index:int):void
		{
			while (_content.numChildren > 0) _content.removeChildAt(0);

			var tab:Object = _tabs[index];
			var y:Number = 6;

			if (tab.sliders != null)
			{
				for each (var s:Object in tab.sliders)
				{
					addSliderRow(s, y);
					y += SLIDER_ROW_H;
				}
			}

			if (tab.kind == "toggle")
			{
				for (var i:int = 0; i < tab.items.length; i++)
				{
					addToggleRow(tab.items[i], y);
					y += ROW_H;
				}
			}
			else if (tab.kind == "style")
			{
				for (var j:int = 0; j < tab.options.length; j++)
				{
					addRow(tab, tab.options[j], y);
					y += ROW_H;
				}
			}
		}

		// ── "style" rows: select one of N, calls Modules.getModule(name).setXXX(id) ─

		private function addRow(tab:Object, opt:Object, y:Number):void
		{
			var isActive:Boolean = (opt.id == tab.current);
			var rowW:Number = CONTENT_W - 12;

			var row:Sprite = new Sprite();
			row.x = 6;
			row.y = y;
			row.buttonMode = true;

			var rowBg:Shape = new Shape();
			drawRowBg(rowBg, rowW, isActive ? COL_ROW_ACTIVE : COL_ROW);
			row.addChild(rowBg);

			var text:TextField = new TextField();
			text.autoSize = TextFieldAutoSize.LEFT;
			text.selectable = false;
			text.mouseEnabled = false;
			text.defaultTextFormat = new TextFormat("Arial", 10.5, isActive ? 0xFFFFFF : COL_TEXT, isActive);
			text.text = opt.label;
			text.x = 12; text.y = 6;
			row.addChild(text);

			if (isActive)
			{
				var dot:Shape = new Shape();
				dot.graphics.beginFill(COL_GOLD, 1);
				dot.graphics.drawCircle(rowW - 14, ROW_H / 2 - 1, 3);
				dot.graphics.endFill();
				row.addChild(dot);
			}

			row.addEventListener(MouseEvent.MOUSE_OVER, function (e:MouseEvent):void
			{
				if (!isActive) drawRowBg(rowBg, rowW, COL_ROW_HOVER);
			});
			row.addEventListener(MouseEvent.MOUSE_OUT, function (e:MouseEvent):void
			{
				if (!isActive) drawRowBg(rowBg, rowW, COL_ROW);
			});

			row.addEventListener(MouseEvent.CLICK, function (e:MouseEvent):void
			{
				try
				{
					tab.current = opt.id;
					if (opt.id == OFF_ID)
					{
						Modules.disable(tab.moduleName);
					}
					else
					{
						if (tab.needsEnable) Modules.enable(tab.moduleName);
						var mod:* = Modules.getModule(tab.moduleName);
						if (mod) mod[tab.setterName](opt.id);
					}
					showTab(_activeTab);
				}
				catch (err:Error)
				{
					debug("row click ERROR (" + tab.moduleName + "): " + err.message);
				}
			});

			_content.addChild(row);
		}

		// ── "toggle" rows: plain on/off, calls Modules.enable(name)/disable(name) ──

		private function addToggleRow(item:Object, y:Number):void
		{
			var mod:* = Modules.getModule(item.name);
			var isOn:Boolean = (mod != null && mod.enabled == true);
			var rowW:Number = CONTENT_W - 12;

			var row:Sprite = new Sprite();
			row.x = 6;
			row.y = y;
			row.buttonMode = true;

			var rowBg:Shape = new Shape();
			drawRowBg(rowBg, rowW, COL_ROW);
			row.addChild(rowBg);

			var text:TextField = new TextField();
			text.autoSize = TextFieldAutoSize.LEFT;
			text.selectable = false;
			text.mouseEnabled = false;
			text.defaultTextFormat = new TextFormat("Arial", 10.5, COL_TEXT, false);
			text.text = item.label;
			text.x = 12; text.y = 6;
			row.addChild(text);

			var sw:Shape = drawToggleSwitch(isOn);
			sw.x = rowW - 38; sw.y = 5;
			row.addChild(sw);

			row.addEventListener(MouseEvent.MOUSE_OVER, function (e:MouseEvent):void { drawRowBg(rowBg, rowW, COL_ROW_HOVER); });
			row.addEventListener(MouseEvent.MOUSE_OUT, function (e:MouseEvent):void { drawRowBg(rowBg, rowW, COL_ROW); });

			row.addEventListener(MouseEvent.CLICK, function (e:MouseEvent):void
			{
				try
				{
					var m:* = Modules.getModule(item.name);
					if (m == null) return;
					if (m.enabled) Modules.disable(item.name);
					else Modules.enable(item.name);
					showTab(_activeTab);
				}
				catch (err:Error)
				{
					debug("toggle click ERROR (" + item.name + "): " + err.message);
				}
			});

			_content.addChild(row);
		}

		// ── slider rows: click-or-drag a track, calls Modules.getModule(name).setXXX(value) ─

		private function addSliderRow(slider:Object, y:Number):void
		{
			var rowW:Number = CONTENT_W - 12;
			var trackW:Number = rowW - 20;
			var trackY:Number = 24;

			var row:Sprite = new Sprite();
			row.x = 6;
			row.y = y;

			var rowBg:Shape = new Shape();
			rowBg.graphics.beginFill(COL_ROW, 1);
			rowBg.graphics.drawRoundRect(0, 0, rowW, SLIDER_ROW_H - 4, 5, 5);
			rowBg.graphics.endFill();
			row.addChild(rowBg);

			var label:TextField = new TextField();
			label.autoSize = TextFieldAutoSize.LEFT;
			label.selectable = false;
			label.mouseEnabled = false;
			label.defaultTextFormat = new TextFormat("Arial", 10.5, COL_TEXT, false);
			label.text = slider.label;
			label.x = 10; label.y = 4;
			row.addChild(label);

			var valueText:TextField = new TextField();
			valueText.autoSize = TextFieldAutoSize.LEFT;
			valueText.selectable = false;
			valueText.mouseEnabled = false;
			valueText.defaultTextFormat = new TextFormat("Arial", 10.5, COL_GOLD, true);
			valueText.text = slider.value + slider.unit;
			valueText.x = rowW - 10 - valueText.textWidth;
			valueText.y = 4;
			row.addChild(valueText);

			var track:Sprite = new Sprite();
			track.x = 10; track.y = trackY;
			track.buttonMode = true;

			var trackBg:Shape = new Shape();
			trackBg.graphics.beginFill(COL_OFF, 1);
			trackBg.graphics.drawRoundRect(0, 0, trackW, 5, 5, 5);
			trackBg.graphics.endFill();
			track.addChild(trackBg);

			var frac:Number = (slider.value - slider.min) / (slider.max - slider.min);

			var fill:Shape = new Shape();
			fill.graphics.beginFill(COL_GOLD, 1);
			fill.graphics.drawRoundRect(0, 0, Math.max(5, trackW * frac), 5, 5, 5);
			fill.graphics.endFill();
			track.addChild(fill);

			var knob:Shape = new Shape();
			knob.graphics.beginFill(0xFFFFFF, 1);
			knob.graphics.lineStyle(1, COL_GOLD);
			knob.graphics.drawCircle(trackW * frac, 2.5, 6);
			knob.graphics.endFill();
			track.addChild(knob);

			row.addChild(track);

			var dragging:Boolean = false;

			function redraw(f:Number):void
			{
				fill.graphics.clear();
				fill.graphics.beginFill(COL_GOLD, 1);
				fill.graphics.drawRoundRect(0, 0, Math.max(5, trackW * f), 5, 5, 5);
				fill.graphics.endFill();

				knob.graphics.clear();
				knob.graphics.beginFill(0xFFFFFF, 1);
				knob.graphics.lineStyle(1, COL_GOLD);
				knob.graphics.drawCircle(trackW * f, 2.5, 6);
				knob.graphics.endFill();

				valueText.text = slider.value + slider.unit;
				valueText.x = rowW - 10 - valueText.textWidth;
			}

			function applyFromLocalX(localX:Number):void
			{
				var f:Number = Math.max(0, Math.min(1, localX / trackW));
				var raw:Number = slider.min + f * (slider.max - slider.min);
				var stepped:Number = Math.round(raw / slider.step) * slider.step;
				stepped = Math.max(slider.min, Math.min(slider.max, stepped));
				if (stepped == slider.value) return;
				slider.value = stepped;
				redraw((slider.value - slider.min) / (slider.max - slider.min));

				try
				{
					if (slider.needsEnable) Modules.enable(slider.moduleName);
					var mod:* = Modules.getModule(slider.moduleName);
					if (mod) mod[slider.setterName](slider.value);
				}
				catch (err:Error)
				{
					debug("slider ERROR (" + slider.moduleName + "): " + err.message);
				}
			}

			function onTrackMove(e:MouseEvent):void
			{
				if (dragging) applyFromLocalX(track.mouseX);
			}

			function onTrackUp(e:MouseEvent):void
			{
				dragging = false;
				_game.stage.removeEventListener(MouseEvent.MOUSE_MOVE, onTrackMove);
				_game.stage.removeEventListener(MouseEvent.MOUSE_UP, onTrackUp);
			}

			track.addEventListener(MouseEvent.MOUSE_DOWN, function (e:MouseEvent):void
			{
				dragging = true;
				applyFromLocalX(track.mouseX);
				_game.stage.addEventListener(MouseEvent.MOUSE_MOVE, onTrackMove);
				_game.stage.addEventListener(MouseEvent.MOUSE_UP, onTrackUp);
			});

			_content.addChild(row);
		}

		private function drawToggleSwitch(isOn:Boolean):Shape
		{
			var sw:Shape = new Shape();
			var trackW:Number = 30, trackH:Number = 15;
			sw.graphics.beginFill(isOn ? COL_GREEN : COL_OFF, 1);
			sw.graphics.drawRoundRect(0, 0, trackW, trackH, trackH, trackH);
			sw.graphics.endFill();
			sw.graphics.beginFill(0xFFFFFF, 1);
			sw.graphics.drawCircle(isOn ? trackW - trackH / 2 : trackH / 2, trackH / 2, trackH / 2 - 2);
			sw.graphics.endFill();
			return sw;
		}

		private function drawRowBg(shape:Shape, w:Number, color:uint):void
		{
			shape.graphics.clear();
			shape.graphics.beginFill(color, 1);
			shape.graphics.drawRoundRect(0, 0, w, ROW_H - 3, 5, 5);
			shape.graphics.endFill();
		}
	}
}
