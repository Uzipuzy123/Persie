package skua.module
{
	import flash.display.Sprite;
	import flash.display.Shape;
	import flash.display.Bitmap;
	import flash.display.BitmapData;
	import flash.events.Event;
	import flash.events.MouseEvent;
	import flash.events.KeyboardEvent;
	import flash.text.TextField;
	import flash.text.TextFormat;
	import flash.text.TextFieldType;
	import flash.text.TextFieldAutoSize;
	import flash.ui.Keyboard;
	import flash.external.ExternalInterface;

	/**
	 * Clickable in-game settings menu, rebuilt to match AQW's native "O" menu
	 * 1:1: a left "Advanced Options" panel (search bar + scrollable settings
	 * list, using the real liteAssets.listOptionsItem row skins) and a right
	 * "Description" panel that shows what the hovered setting does — the same
	 * two-panel split the native mcOption symbol uses (Advanced Options /
	 * Options), just with the right side repurposed since we don't have a
	 * fixed native settings list to mirror there.
	 *
	 * Every setting is one row in the flat scrollable list:
	 *  - "style": inline ◄ value ► cycle control, calls
	 *    Modules.getModule(name).setXXX(id). PlayerHPBars is a special case —
	 *    it has no dedicated "off" style id (id 0 is a real style, "LoL"), so
	 *    its cycle list uses a sentinel id of -1 for "Off" (Modules.disable()
	 *    instead of setStyle()); any other id calls Modules.enable()
	 *    (needsEnable:true) then setStyle(id).
	 *  - "toggle": checkbox control, calls Modules.enable(name)/disable(name) —
	 *    reads the module's real `enabled` field each render rather than
	 *    tracking state locally, so it can never drift out of sync.
	 *  - "slider": drag track, calls Modules.getModule(name).setXXX(value).
	 *
	 * Ctrl+M toggles the panel. No host application involved — everything
	 * here calls straight into the same AS3 module methods Main.as's
	 * ExternalInterface callbacks already wrap.
	 */
	public class IngameMenu extends Module
	{
		// ── layout ────────────────────────────────────────────────────────────
		private static const TITLE_H:Number     = 28;
		private static const LEFT_W:Number      = 340;
		private static const RIGHT_W:Number     = 220;
		private static const PANEL_GAP:Number   = 10;
		private static const PANEL_H:Number     = 470;
		private static const SUB_HEADER_H:Number = 24;
		private static const SEARCH_H:Number    = 26;
		private static const ROW_H:Number       = 28;
		private static const SLIDER_ROW_H:Number = 40;
		private static const SECTION_H:Number   = 20;
		private static const CHECKBOX_W:Number  = 18;
		private static const CHECKBOX_H:Number  = 16;
		private static const SCROLL_ARROW_ZONE:Number = 18; // reserved top/bottom track space for the arrow buttons
		private static const OFF_ID:int = -1;

		// ── palette (sampled straight from AQW's native mcOption panel) ──────
		private static const COL_BG:uint        = 0x000000; // panel fill, drawn at ~85% alpha
		private static const COL_BG_ALPHA:Number = 0.85;
		private static const COL_ROW_ALT:uint   = 0x0A0A0A;
		private static const COL_ROW_HOVER:uint = 0x1C1C1C;
		private static const COL_BORDER_HI:uint = 0xB77E22; // gold border highlight
		private static const COL_BORDER_LO:uint = 0x5D3218; // gold border shadow/bevel
		private static const COL_TEXT:uint      = 0xF2E9D8;
		private static const COL_GOLD:uint      = 0xE0B24A;
		private static const COL_GREEN:uint     = 0x2FBF71;
		private static const COL_OFF:uint       = 0x565C6B;

		// ── native row-control icons (liteAssets.listOptionsItem.*, exported via FFDec) ─
		[Embed(source="../assets/opt_arrow_left.png")]
		private static const ArrowLeftArt:Class;
		[Embed(source="../assets/opt_arrow_right.png")]
		private static const ArrowRightArt:Class;
		[Embed(source="../assets/opt_checkbox.png")]
		private static const CheckboxArt:Class;
		[Embed(source="../assets/opt_search_icon.png")]
		private static const SearchIconArt:Class;
		[Embed(source="../assets/opt_scroll_arrow.png")]
		private static const ScrollArrowArt:Class;

		private var _game:*;
		private var _panel:Sprite;
		private var _titleBar:Sprite;

		private var _leftPanel:Sprite;
		private var _searchField:TextField;
		private var _listViewport:Sprite;
		private var _listMask:Shape;
		private var _listContent:Sprite;
		private var _scrollTrack:Sprite;
		private var _scrollThumb:Sprite;
		private var _scrollY:Number = 0;
		private var _listVisibleH:Number;

		private var _rightPanel:Sprite;
		private var _descTitle:TextField;
		private var _descBody:TextField;
		private var _descOptions:Sprite;

		private var _settings:Array;

		public function IngameMenu() { super("IngameMenu"); }

		override public function onToggle(game:*):void
		{
			_game = game;
			if (enabled)
			{
				game.stage.addEventListener(KeyboardEvent.KEY_UP, onKeyUp);
				if (_settings == null) buildSettingsList();
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

		// ── icon helpers ──────────────────────────────────────────────────────

		private static function iconBitmap(cls:Class):Bitmap
		{
			var b:Bitmap = new cls() as Bitmap;
			b.smoothing = true;
			return b;
		}

		// Bitmap extends DisplayObject, not InteractiveObject — it can't take
		// buttonMode or mouse listeners on its own, so clickable icons need a
		// Sprite wrapper (the wrapper's hit area comes from its bitmap
		// child's rendered bounds, same as any other Shape-in-a-Sprite row).
		private static function iconButton(cls:Class, scale:Number):Sprite
		{
			var btn:Sprite = new Sprite();
			btn.buttonMode = true;
			var b:Bitmap = iconBitmap(cls);
			b.scaleX = b.scaleY = scale;
			btn.addChild(b);
			return btn;
		}

		// ── settings data (flattened — one entry per row in the scrollable list) ─

		private function buildSettingsList():void
		{
			_settings = [];

			addSection("Styles");

			addStyle("HUD", "SelfHud", "setStyle", [
				{id:0,label:"Default"},{id:1,label:"Sleek Gradient"},{id:2,label:"Tactical"},
				{id:3,label:"Neon"},{id:4,label:"Ornate"},{id:5,label:"Hex Plate"},
				{id:6,label:"Liquid"},{id:7,label:"Angular"},{id:8,label:"Gothic Blood"},{id:9,label:"Orb"}
			], "Reskins your own health/mana/XP bar HUD overlay.");

			addStyle("Skill Bar", "SkillBarSkin", "setStyle", [
				{id:0,label:"Default"},{id:1,label:"Hex Grid"}
			], "Reskins your action bar's skill icon frames.");

			addStyle("Blue Flag", "TeamFlagReskin", "setBlueStyle", [
				{id:0,label:"Default"},{id:1,label:"Rising Sun"},{id:2,label:"Shuriken"},
				{id:3,label:"Sakura"},{id:4,label:"Lightning Bolt"},{id:5,label:"Crescent Moon"},{id:6,label:"Katana"}
			], "Changes the blue team's capture flag icon.");

			addStyle("Red Flag", "TeamFlagReskin", "setRedStyle", [
				{id:0,label:"Default"},{id:1,label:"Flame"},{id:2,label:"Oni Eye"},
				{id:3,label:"Demon Horns"},{id:4,label:"Claw Marks"},{id:5,label:"Blood Drop"},{id:6,label:"Phoenix Wing"}
			], "Changes the red team's capture flag icon.");

			addStyle("Scoreboard", "ScoreboardSkin", "setSkin", [
				{id:0,label:"Default"},{id:1,label:"Esports"},{id:2,label:"Neon Bar"},{id:3,label:"Radial"},
				{id:4,label:"Orb"},{id:5,label:"Dial"},{id:6,label:"Hex"},{id:7,label:"Diamond"}
			], "Reskins the match scoreboard's look.");

			addStyle("Nameplate", "NameplateFont", "setFont", [
				{id:0,label:"Default"},{id:1,label:"Comic Sans"},{id:2,label:"Impact"},{id:3,label:"Papyrus"},
				{id:4,label:"Arial Black"},{id:5,label:"Consolas"},{id:6,label:"Segoe Script"},{id:7,label:"Gabriola"},
				{id:8,label:"MV Boli"},{id:9,label:"Bahnschrift"},{id:10,label:"Ink Free"},{id:11,label:"Golden Royalty"},
				{id:12,label:"Ancient Blood"},{id:13,label:"Toxic Glow"},{id:14,label:"Frostbite"},{id:15,label:"Cyber Pink"}
			], "Changes the font used for player nameplates.");

			addStyle("Self Outline", "SelfOutline", "setColor", [
				{id:0,label:"Off"},{id:1,label:"Cyan"},{id:2,label:"White"},{id:3,label:"Gold"},{id:4,label:"Green"},
				{id:5,label:"Red"},{id:6,label:"Blue"},{id:7,label:"Purple"},{id:8,label:"Pink"}
			], "Adds a colored outline around your own character.");

			addStyle("Enemy Outline", "EnemyOutline", "setColor", [
				{id:0,label:"Off"},{id:1,label:"Red"},{id:2,label:"Orange"},{id:3,label:"White"},{id:4,label:"Gold"},
				{id:5,label:"Purple"},{id:6,label:"Magenta"},{id:7,label:"Green"},{id:8,label:"Cyan"}
			], "Adds a colored outline around enemy characters.");

			addStyle("My Hit Style", "HitFlash", "setMyStyle", hitStyleOptions(),
				"Flash effect shown when you land a hit.");

			addStyle("Enemy Hit Style", "HitFlash", "setEnemyStyle", hitStyleOptions(),
				"Flash effect shown when an enemy lands a hit on you.");

			addStyle("Vignette", "Vignette", "setStyle", [
				{id:0,label:"Off"},{id:1,label:"Classic Shadow"},{id:2,label:"Heavy Black"},{id:3,label:"Blood Red"},
				{id:4,label:"Cold Blue"},{id:5,label:"Mystic Purple"},{id:6,label:"Warm Gold"},{id:7,label:"Forest Green"},
				{id:8,label:"Teal Mist"},{id:9,label:"Pulse Dark"},{id:10,label:"Pulse Red"},{id:11,label:"Soft Fade"}
			], "Adds a screen-edge vignette effect.");

			addStyle("Kill Flash Screen", "KillFlash", "setScreenStyle", [
				{id:0,label:"Off"},{id:1,label:"White Flash"},{id:2,label:"Red Rush"},{id:3,label:"Gold Strike"},
				{id:4,label:"Blue Freeze"},{id:5,label:"Purple Hex"},{id:6,label:"Green Vengeance"},{id:7,label:"Pink Burst"},
				{id:8,label:"Teal Wave"},{id:9,label:"Double White"},{id:10,label:"Double Red"},{id:11,label:"Orange Fury"}
			], "Full-screen flash effect on a kill.");

			addStyle("Kill Flash Player", "KillFlash", "setPlayerStyle", [
				{id:0,label:"Off"},{id:1,label:"Bleach White"},{id:2,label:"Blood Splatter"},{id:3,label:"Gold Victory"},
				{id:4,label:"Ice Blue"},{id:5,label:"Ghost"},{id:6,label:"Purple Curse"},{id:7,label:"Orange Burn"},
				{id:8,label:"Void Black"},{id:9,label:"Electric Pink"}
			], "Flash effect on the killed player's body.");

			// PlayerHPBars has no dedicated "off" style id — id 0 is a real
			// style (LoL). OFF_ID is a sentinel this file interprets specially
			// (Modules.disable instead of setStyle); needsEnable:true means
			// every other id calls Modules.enable() first, since the module
			// starts disabled and setStyle() alone wouldn't make it render.
			addStyle("HP Bar", "PlayerHPBars", "setStyle", [
				{id:OFF_ID,label:"Off"},
				{id:0,label:"LoL"},{id:1,label:"WoW"},{id:2,label:"Fortnite"},{id:3,label:"Valorant"},
				{id:4,label:"Rune"},{id:5,label:"Overwatch"},{id:6,label:"Elden Ring"},{id:7,label:"GTA"},
				{id:8,label:"Minecraft"},{id:9,label:"Neon Glow"},{id:10,label:"Gradient"},
				{id:11,label:"Pixel Blocks"},{id:12,label:"AQW Gold"}
			], "Custom overhead HP bar style for all players.", true, OFF_ID);

			addSlider("HP Bar Size", "PlayerHPBars", "setScale", 10, 100, 60, 5, "%", true,
				"Scales the size of the custom HP bars.");

			addSection("Toggles");

			addToggle("ClearFilters", "Clear Filters", "Strips visual filters (blur/glow) from the scene for performance.");
			addToggle("StopAnimations", "Freeze BG", "Freezes background animations to save CPU.");
			addToggle("KillParticles", "Kill Particles", "Disables particle effects entirely.");
			addToggle("OptimizeMap", "Optimize Map", "Simplifies map rendering for better performance.");
			addToggle("MuteGame", "Mute Audio", "Mutes all game audio.");
			addToggle("DisableShadows", "Disable Shadows", "Removes character/object drop shadows.");
			addToggle("HighlightEnemies", "Highlight Enemies", "Adds a highlight effect to enemy players.");
			addToggle("HideAllHelms", "Hide All Helms", "Hides every other player's helm, locally only.");
			addToggle("HideAllWeapons", "Hide All Weapons", "Hides every other player's weapon and offhand, locally only.");
			addToggle("HideAllCapesLocal", "Hide All Capes", "Hides every other player's cape, locally only.");
			addToggle("HideAllRobes", "Hide All Robes", "Hides every other player's robe, locally only.");

			addSlider("FPS Limiter", "FpsControl", "setFps", 24, 60, 30, 1, " FPS", false,
				"Caps the game's frame rate.");

			addSection("Overlays");

			addToggle("MiniMap", "Mini Map", "Shows a mini-map overlay.");
			addToggle("KillFeed", "Kill Feed", "Shows a kill-feed overlay of recent kills.");
			addToggle("EnemyHPOverlay", "HP Overlay", "Shows enemy HP as an overlay.");
			addToggle("ScoreboardOverlay", "Scoreboard", "Shows a scoreboard overlay.");
			addToggle("DebugPanel", "Debug Panel", "Shows an internal debug info panel.");
			addToggle("SkuaSettingsButton", "Ingame Button", "Shows a clickable Skua settings button in the UI.");
			addToggle("MapSkin", "Bludrutbrawl Skin", "Replaces select Bludrutbrawl room backgrounds with custom art.");
			addToggle("YulgarSkin", "Yulgar Skin (Max Quality)", "Replaces Yulgar's Enter room background with max-quality custom art.");
			addToggle("MapDebug", "Map Debug", "Calibration tool for positioning map-skin art.");

			addSection("Effects");

			addToggle("PortalFlash", "Portal Flash", "Flash effect when using a portal.");
			addToggle("RespawnEffect", "Respawn Effect", "Visual effect played on respawn.");
			addToggle("DisableNativeGlow", "Disable All Glow", "Disables the game's native glow filter effects.");
			addToggle("DisableNativeAnimation", "Disable All Animation", "Disables the game's native animated effects.");
			addToggle("LowHPFlash", "Low HP Flash", "Flashes the screen red at low HP.");
			addToggle("RevengeKill", "Revenge Kill", "Highlights when you kill someone who killed you.");
			addToggle("KillStreakAnnouncer", "Kill Streak Announcer", "Announces kill streaks on screen.");
			addToggle("AntiCamp", "Anti-Camp Damage", "Camping over 3s in your own team's safe room (Morale0A/Morale1A) triggers repeated real damage via the game's own aggroAllMon(), pausing whenever your HP drops to 1500 or below.");
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
			_settings.push({ kind:"section", label:label });
		}

		private function addStyle(label:String, moduleName:String, setterName:String, options:Array, desc:String, needsEnable:Boolean = false, defaultId:int = 0):void
		{
			_settings.push({ kind:"style", label:label, moduleName:moduleName, setterName:setterName,
				options:options, current:defaultId, needsEnable:needsEnable, desc:desc });
		}

		private function addToggle(name:String, label:String, desc:String):void
		{
			_settings.push({ kind:"toggle", name:name, label:label, desc:desc });
		}

		private function addSlider(label:String, moduleName:String, setterName:String, min:Number, max:Number, value:Number, step:Number, unit:String, needsEnable:Boolean, desc:String):void
		{
			_settings.push({ kind:"slider", label:label, moduleName:moduleName, setterName:setterName,
				min:min, max:max, value:value, step:step, unit:unit, needsEnable:needsEnable, desc:desc });
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
			// Panel margin (6px) is reserved on BOTH sides — the right panel's
			// x plus its own width must land 6px short of totalW, not flush
			// with it, or its content renders past the outer border.
			var totalW:Number = 6 + LEFT_W + PANEL_GAP + RIGHT_W + 6;

			_panel = new Sprite();
			_panel.x = 160;
			_panel.y = 30;

			var frame:Shape = new Shape();
			frame.graphics.beginFill(COL_BG, COL_BG_ALPHA);
			frame.graphics.drawRoundRect(0, 0, totalW, TITLE_H + PANEL_H, 10, 10);
			frame.graphics.endFill();
			_panel.addChild(frame);
			_panel.addChild(buildGoldBorder(totalW, TITLE_H + PANEL_H));

			buildTitleBar(totalW);
			buildLeftPanel();
			buildRightPanel();

			_leftPanel.x = 6;
			_leftPanel.y = TITLE_H + 6;
			_panel.addChild(_leftPanel);

			_rightPanel.x = 6 + LEFT_W + PANEL_GAP;
			_rightPanel.y = TITLE_H + 6;
			_panel.addChild(_rightPanel);

			rebuildList();
			showDescription(null);

			_game.stage.addChild(_panel);
		}

		// Beveled gold frame matching mcOption's border: a lighter gold pass
		// then a darker brown-gold pass offset by 1px on the shadow side, so
		// the two-tone edge reads as a raised ornate bevel rather than a flat line.
		private function buildGoldBorder(w:Number, h:Number):Shape
		{
			var s:Shape = new Shape();
			s.graphics.lineStyle(2, COL_BORDER_LO, 1);
			s.graphics.drawRoundRect(1, 1, w - 2, h - 2, 10, 10);
			s.graphics.lineStyle(1.5, COL_BORDER_HI, 1);
			s.graphics.drawRoundRect(0, 0, w - 1, h - 1, 10, 10);
			return s;
		}

		// ── title bar: drag handle + close button ───────────────────────────

		private function buildTitleBar(totalW:Number):void
		{
			_titleBar = new Sprite();
			_titleBar.buttonMode = true;

			var bg:Shape = new Shape();
			bg.graphics.beginFill(0x000000, COL_BG_ALPHA);
			bg.graphics.drawRoundRectComplex(0, 0, totalW, TITLE_H, 10, 10, 0, 0);
			bg.graphics.endFill();
			bg.graphics.lineStyle(1, COL_BORDER_HI, 0.6);
			bg.graphics.moveTo(0, TITLE_H - 0.5);
			bg.graphics.lineTo(totalW, TITLE_H - 0.5);
			_titleBar.addChild(bg);

			var title:TextField = new TextField();
			title.autoSize = TextFieldAutoSize.CENTER;
			title.selectable = false;
			title.mouseEnabled = false;
			title.defaultTextFormat = new TextFormat("Georgia", 14, COL_TEXT, false, true);
			title.text = "GunLive";
			title.width = totalW;
			title.x = 0; title.y = 3;
			_titleBar.addChild(title);

			var close:Sprite = buildCloseButton();
			close.x = totalW - 22;
			close.y = 5;
			_titleBar.addChild(close);

			_titleBar.addEventListener(MouseEvent.MOUSE_DOWN, onDragStart);
			_panel.addChild(_titleBar);
		}

		private function buildCloseButton():Sprite
		{
			var btn:Sprite = new Sprite();
			btn.buttonMode = true;

			var bg:Shape = new Shape();
			bg.graphics.lineStyle(2, COL_BORDER_HI, 1);
			bg.graphics.beginFill(0x8A1414, 1);
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

		private function subHeader(text:String, w:Number):Sprite
		{
			var header:Sprite = new Sprite();
			var bg:Shape = new Shape();
			bg.graphics.beginFill(0x000000, 1);
			bg.graphics.lineStyle(1, COL_BORDER_HI, 0.6);
			bg.graphics.drawRect(0, 0, w, SUB_HEADER_H);
			bg.graphics.endFill();
			header.addChild(bg);

			var tf:TextField = new TextField();
			tf.autoSize = TextFieldAutoSize.CENTER;
			tf.selectable = false;
			tf.mouseEnabled = false;
			tf.defaultTextFormat = new TextFormat("Georgia", 12, COL_TEXT, false, true);
			tf.text = text;
			tf.width = w;
			tf.x = 0; tf.y = 2;
			header.addChild(tf);

			return header;
		}

		// ── left panel: "Advanced Options" — search bar + scrollable list ────

		private function buildLeftPanel():void
		{
			_leftPanel = new Sprite();
			_leftPanel.addChild(subHeader("Advanced Options", LEFT_W));

			buildSearchBar();

			_listVisibleH = PANEL_H - 12 - SUB_HEADER_H - SEARCH_H;

			_listViewport = new Sprite();
			_listViewport.x = 0;
			_listViewport.y = SUB_HEADER_H + SEARCH_H;
			_leftPanel.addChild(_listViewport);

			// Adding the mask shape to the display list keeps its coordinate
			// space locked to the same parent as the content it clips (this
			// whole panel is draggable) — Flash never actually renders a
			// DisplayObject once it's assigned as another object's .mask, so
			// this stays invisible regardless.
			_listMask = new Shape();
			_listMask.graphics.beginFill(0xFF00FF, 1);
			_listMask.graphics.drawRect(0, 0, LEFT_W - 16, _listVisibleH);
			_listMask.graphics.endFill();
			_listViewport.addChild(_listMask);

			_listContent = new Sprite();
			_listContent.mask = _listMask;
			_listViewport.addChild(_listContent);

			_listViewport.addEventListener(MouseEvent.MOUSE_WHEEL, onListWheel);

			buildScrollbar();
		}

		private function buildSearchBar():void
		{
			var bar:Sprite = new Sprite();
			bar.y = SUB_HEADER_H;

			var bg:Shape = new Shape();
			bg.graphics.beginFill(0x000000, 1);
			bg.graphics.lineStyle(1, COL_BORDER_LO, 1);
			bg.graphics.drawRect(0, 0, LEFT_W, SEARCH_H);
			bg.graphics.endFill();
			bar.addChild(bg);

			_searchField = new TextField();
			_searchField.type = TextFieldType.INPUT;
			_searchField.background = false;
			_searchField.border = false;
			_searchField.defaultTextFormat = new TextFormat("Arial", 10.5, COL_TEXT, false);
			_searchField.text = "";
			_searchField.width = LEFT_W - 60;
			_searchField.height = SEARCH_H - 6;
			_searchField.x = 8; _searchField.y = 3;
			bar.addChild(_searchField);

			var hint:TextField = new TextField();
			hint.selectable = false;
			hint.mouseEnabled = false;
			hint.defaultTextFormat = new TextFormat("Arial", 9, COL_OFF, false, true);
			hint.text = "search settings...";
			hint.x = 8; hint.y = 4;
			hint.width = LEFT_W - 60;
			hint.visible = true;
			bar.addChild(hint);

			var icon:Bitmap = iconBitmap(SearchIconArt);
			icon.height = SEARCH_H - 8;
			icon.width = icon.height * (30 / 33);
			icon.x = LEFT_W - icon.width - 6; icon.y = 4;
			bar.addChild(icon);

			_searchField.addEventListener(Event.CHANGE, function (e:Event):void
			{
				hint.visible = (_searchField.text.length == 0);
				rebuildList();
			});

			_leftPanel.addChild(bar);
		}

		private function buildScrollbar():void
		{
			_scrollTrack = new Sprite();
			_scrollTrack.x = LEFT_W - 14;
			_scrollTrack.y = SUB_HEADER_H + SEARCH_H;

			var track:Shape = new Shape();
			track.graphics.lineStyle(1, COL_BORDER_LO, 1);
			track.graphics.beginFill(0x000000, 1);
			track.graphics.drawRoundRect(0, 0, 10, _listVisibleH, 5, 5);
			track.graphics.endFill();
			_scrollTrack.addChild(track);

			// Native arrow art is 30x26 at this 0.55 scale -> ~16.5x14.3
			// rendered. Kept INSET within the track's own vertical bounds
			// (not poking out above/below it) so they can never overlap the
			// search bar's icon sitting right above this track.
			var arrowScale:Number = 0.55;
			var arrowW:Number = 30 * arrowScale;
			var arrowH:Number = 26 * arrowScale;
			var arrowX:Number = (10 - arrowW) / 2;

			var up:Sprite = new Sprite();
			up.buttonMode = true;
			var upBmp:Bitmap = iconBitmap(ScrollArrowArt);
			upBmp.scaleX = upBmp.scaleY = arrowScale;
			up.addChild(upBmp);
			up.x = arrowX; up.y = (SCROLL_ARROW_ZONE - arrowH) / 2;
			up.addEventListener(MouseEvent.CLICK, function (e:MouseEvent):void { scrollBy(-ROW_H); });
			_scrollTrack.addChild(up);

			// Down arrow is the same native up-arrow glyph flipped vertically —
			// the game only ever draws the one triangle asset.
			var down:Sprite = new Sprite();
			down.buttonMode = true;
			var downBmp:Bitmap = iconBitmap(ScrollArrowArt);
			downBmp.scaleX = arrowScale; downBmp.scaleY = -arrowScale;
			down.addChild(downBmp);
			down.x = arrowX; down.y = _listVisibleH - (SCROLL_ARROW_ZONE - arrowH) / 2;
			down.addEventListener(MouseEvent.CLICK, function (e:MouseEvent):void { scrollBy(ROW_H); });
			_scrollTrack.addChild(down);

			_scrollThumb = new Sprite();
			_scrollTrack.addChild(_scrollThumb);

			_scrollThumb.buttonMode = true;
			var dragging:Boolean = false;
			var dragStartY:Number = 0;
			var dragStartScroll:Number = 0;

			_scrollThumb.addEventListener(MouseEvent.MOUSE_DOWN, function (e:MouseEvent):void
			{
				dragging = true;
				dragStartY = _game.stage.mouseY;
				dragStartScroll = _scrollY;
				_game.stage.addEventListener(MouseEvent.MOUSE_MOVE, onThumbMove);
				_game.stage.addEventListener(MouseEvent.MOUSE_UP, onThumbUp);
			});

			function onThumbMove(e:MouseEvent):void
			{
				if (!dragging) return;
				var contentH:Number = _listContent.height;
				var maxScroll:Number = Math.max(0, contentH - _listVisibleH);
				var trackFree:Number = (_listVisibleH - SCROLL_ARROW_ZONE * 2) - thumbHeight();
				if (trackFree <= 0) return;
				var deltaPx:Number = _game.stage.mouseY - dragStartY;
				var deltaScroll:Number = (deltaPx / trackFree) * maxScroll;
				setScroll(dragStartScroll + deltaScroll);
			}

			function onThumbUp(e:MouseEvent):void
			{
				dragging = false;
				_game.stage.removeEventListener(MouseEvent.MOUSE_MOVE, onThumbMove);
				_game.stage.removeEventListener(MouseEvent.MOUSE_UP, onThumbUp);
			}

			_leftPanel.addChild(_scrollTrack);
		}

		private function thumbHeight():Number
		{
			var insetH:Number = _listVisibleH - SCROLL_ARROW_ZONE * 2;
			var contentH:Number = (_listContent != null) ? _listContent.height : _listVisibleH;
			if (contentH <= 0) contentH = _listVisibleH;
			var ratio:Number = Math.min(1, _listVisibleH / contentH);
			return Math.max(16, insetH * ratio);
		}

		private function redrawThumb():void
		{
			var insetH:Number = _listVisibleH - SCROLL_ARROW_ZONE * 2;
			var contentH:Number = (_listContent != null) ? _listContent.height : _listVisibleH;
			var maxScroll:Number = Math.max(0, contentH - _listVisibleH);
			var th:Number = thumbHeight();
			var trackFree:Number = insetH - th;
			var frac:Number = (maxScroll <= 0) ? 0 : (_scrollY / maxScroll);

			_scrollThumb.graphics.clear();
			_scrollThumb.graphics.lineStyle(1, COL_BORDER_HI, 1);
			_scrollThumb.graphics.beginFill(0x7A2020, 1);
			_scrollThumb.graphics.drawRoundRect(0, SCROLL_ARROW_ZONE + trackFree * frac, 10, th, 5, 5);
			_scrollThumb.graphics.endFill();
		}

		private function onListWheel(e:MouseEvent):void
		{
			scrollBy(-e.delta * 6);
		}

		private function scrollBy(delta:Number):void
		{
			setScroll(_scrollY + delta);
		}

		private function setScroll(y:Number):void
		{
			var contentH:Number = (_listContent != null) ? _listContent.height : 0;
			var maxScroll:Number = Math.max(0, contentH - _listVisibleH);
			_scrollY = Math.max(0, Math.min(maxScroll, y));
			_listContent.y = -_scrollY;
			redrawThumb();
		}

		// ── right panel: description ─────────────────────────────────────────

		private function buildRightPanel():void
		{
			_rightPanel = new Sprite();
			_rightPanel.addChild(subHeader("Description", RIGHT_W));

			_descTitle = new TextField();
			_descTitle.selectable = false;
			_descTitle.mouseEnabled = false;
			_descTitle.defaultTextFormat = new TextFormat("Georgia", 13, COL_GOLD, true, true);
			_descTitle.width = RIGHT_W - 16;
			_descTitle.height = 22;
			_descTitle.x = 8; _descTitle.y = SUB_HEADER_H + 10;
			_rightPanel.addChild(_descTitle);

			_descBody = new TextField();
			_descBody.selectable = false;
			_descBody.mouseEnabled = false;
			_descBody.multiline = true;
			_descBody.wordWrap = true;
			_descBody.defaultTextFormat = new TextFormat("Arial", 10.5, COL_TEXT, false);
			_descBody.width = RIGHT_W - 16;
			_descBody.height = 70;
			_descBody.x = 8; _descBody.y = SUB_HEADER_H + 36;
			_rightPanel.addChild(_descBody);

			// Lists every choice for the hovered/selected setting (style
			// options, On/Off, or the slider's range) so you don't have to
			// blindly click the cycle arrows to see what's available — and
			// each one is clickable here too, applying immediately and
			// refreshing the matching row on the left.
			_descOptions = new Sprite();
			_descOptions.x = 8; _descOptions.y = _descBody.y + _descBody.height + 10;
			_rightPanel.addChild(_descOptions);
		}

		private function showDescription(entry:Object):void
		{
			while (_descOptions.numChildren > 0) _descOptions.removeChildAt(0);

			if (entry == null)
			{
				_descTitle.text = "Skua Settings";
				_descBody.text = "Hover over a setting on the left to see what it does.";
				return;
			}
			_descTitle.text = entry.label;
			_descBody.text = entry.desc;
			buildOptionsList(entry);
		}

		// Builds the clickable "OPTIONS"/"RANGE" listing under the description
		// text, gold-highlighting whichever choice is currently active so it
		// reads like a legend rather than just a hover tooltip — clicking an
		// option here applies it immediately, same as the left list's controls.
		private function buildOptionsList(entry:Object):void
		{
			var y:Number = 0;

			var header:TextField = new TextField();
			header.selectable = false;
			header.mouseEnabled = false;
			header.autoSize = TextFieldAutoSize.LEFT;
			header.defaultTextFormat = new TextFormat("Arial", 10, COL_GOLD, true);
			header.text = (entry.kind == "slider") ? "RANGE" : "OPTIONS";
			header.y = y;
			_descOptions.addChild(header);
			y += 18;

			if (entry.kind == "style")
			{
				for each (var o:Object in entry.options)
				{
					addStyleOptionRow(entry, o, y);
					y += 18;
				}
			}
			else if (entry.kind == "toggle")
			{
				var mod:* = Modules.getModule(entry.name);
				var isOn:Boolean = (mod != null && mod.enabled == true);

				addDescOptionRow("On", isOn, y, function ():void
				{
					Modules.enable(entry.name);
					rebuildList();
					showDescription(entry);
				});
				y += 18;

				addDescOptionRow("Off", !isOn, y, function ():void
				{
					Modules.disable(entry.name);
					rebuildList();
					showDescription(entry);
				});
				y += 18;
			}
			else if (entry.kind == "slider")
			{
				var rangeText:TextField = new TextField();
				rangeText.selectable = false;
				rangeText.mouseEnabled = false;
				rangeText.autoSize = TextFieldAutoSize.LEFT;
				rangeText.defaultTextFormat = new TextFormat("Arial", 10, 0x8A8378, false);
				rangeText.text = entry.min + entry.unit + " to " + entry.max + entry.unit + ", step " + entry.step + entry.unit;
				rangeText.y = y;
				_descOptions.addChild(rangeText);
			}
		}

		// Isolated into its own function (not an inline closure inside the
		// "for each" loop in buildOptionsList) so each row's click handler
		// captures its OWN `o` parameter — a shared loop variable would let
		// every row apply whichever option happened to be last in the list.
		private function addStyleOptionRow(entry:Object, o:Object, y:Number):void
		{
			addDescOptionRow(o.label, o.id == entry.current, y, function ():void
			{
				entry.current = o.id;
				applyStyleEntry(entry);
				rebuildList();
				showDescription(entry);
			});
		}

		private function addDescOptionRow(label:String, isCurrent:Boolean, y:Number, onClick:Function):void
		{
			var row:Sprite = new Sprite();
			row.y = y;
			row.buttonMode = true;

			var hit:Shape = new Shape();
			hit.graphics.beginFill(0x000000, 0);
			hit.graphics.drawRect(0, 0, RIGHT_W - 16, 16);
			hit.graphics.endFill();
			row.addChild(hit);

			var tf:TextField = new TextField();
			tf.selectable = false;
			tf.mouseEnabled = false;
			tf.autoSize = TextFieldAutoSize.LEFT;
			tf.defaultTextFormat = new TextFormat("Arial", 10, isCurrent ? COL_GOLD : 0x8A8378, isCurrent);
			tf.text = (isCurrent ? "▶ " : "     ") + label;
			row.addChild(tf);

			row.addEventListener(MouseEvent.MOUSE_OVER, function (e:MouseEvent):void { tf.textColor = COL_GOLD; });
			row.addEventListener(MouseEvent.MOUSE_OUT, function (e:MouseEvent):void { tf.textColor = isCurrent ? COL_GOLD : 0x8A8378; });
			row.addEventListener(MouseEvent.CLICK, function (e:MouseEvent):void { onClick(); });

			_descOptions.addChild(row);
		}

		// ── list building/filtering ───────────────────────────────────────────

		private function rebuildList():void
		{
			while (_listContent.numChildren > 0) _listContent.removeChildAt(0);

			var filter:String = (_searchField.text as String).toLowerCase();
			var y:Number = 0;
			var i:int;

			// Pre-scan: does this section have any row that survives the filter?
			var sectionHasMatch:Boolean = true;
			for (i = 0; i < _settings.length; i++)
			{
				var entry:Object = _settings[i];
				if (entry.kind == "section")
				{
					sectionHasMatch = sectionMatches(i, filter);
					if (sectionHasMatch)
					{
						addListSectionLabel(entry.label, y);
						y += SECTION_H;
					}
					continue;
				}
				if (!sectionHasMatch) continue;
				if (filter.length > 0 && entry.label.toLowerCase().indexOf(filter) == -1) continue;

				if (entry.kind == "style") { addStyleRow(entry, y); y += ROW_H; }
				else if (entry.kind == "toggle") { addToggleRow(entry, y); y += ROW_H; }
				else if (entry.kind == "slider") { addSliderRow(entry, y); y += SLIDER_ROW_H; }
			}

			setScroll(_scrollY);
		}

		private function sectionMatches(sectionIndex:int, filter:String):Boolean
		{
			if (filter.length == 0) return true;
			for (var j:int = sectionIndex + 1; j < _settings.length; j++)
			{
				var e:Object = _settings[j];
				if (e.kind == "section") break;
				if (e.label.toLowerCase().indexOf(filter) != -1) return true;
			}
			return false;
		}

		private function addListSectionLabel(label:String, y:Number):void
		{
			var tf:TextField = new TextField();
			tf.autoSize = TextFieldAutoSize.LEFT;
			tf.selectable = false;
			tf.mouseEnabled = false;
			tf.defaultTextFormat = new TextFormat("Consolas", 8, COL_GOLD, true);
			tf.text = "─ " + label.toUpperCase();
			tf.x = 6; tf.y = y + 4;
			_listContent.addChild(tf);
		}

		// Shared by the left list's cycle arrows and the description panel's
		// clickable options list, so both entry points stay in sync.
		private function applyStyleEntry(entry:Object):void
		{
			try
			{
				if (entry.current == OFF_ID)
				{
					Modules.disable(entry.moduleName);
				}
				else
				{
					if (entry.needsEnable) Modules.enable(entry.moduleName);
					var mod:* = Modules.getModule(entry.moduleName);
					if (mod) mod[entry.setterName](entry.current);
				}
			}
			catch (err:Error)
			{
				debug("style row ERROR (" + entry.moduleName + "): " + err.message);
			}
		}

		// ── "style" rows: inline ◄ value ► cycle control ─────────────────────

		private function addStyleRow(entry:Object, y:Number):void
		{
			var rowW:Number = LEFT_W - 16;
			var row:Sprite = new Sprite();
			row.y = y;

			var rowBg:Shape = new Shape();
			drawListRowBg(rowBg, rowW, false);
			row.addChild(rowBg);

			var label:TextField = new TextField();
			label.autoSize = TextFieldAutoSize.LEFT;
			label.selectable = false;
			label.mouseEnabled = false;
			label.defaultTextFormat = new TextFormat("Arial", 10, COL_TEXT, false);
			label.text = entry.label;
			label.x = 8; label.y = 7;
			row.addChild(label);

			var valueText:TextField = new TextField();
			valueText.autoSize = TextFieldAutoSize.CENTER;
			valueText.selectable = false;
			valueText.mouseEnabled = false;
			valueText.defaultTextFormat = new TextFormat("Arial", 10, COL_GOLD, true);

			function currentLabel():String
			{
				for each (var o:Object in entry.options)
					if (o.id == entry.current) return o.label;
				return "";
			}

			function redrawValue():void
			{
				valueText.text = currentLabel();
				valueText.width = 90;
				valueText.x = rowW - 84;
				valueText.y = 7;
			}
			redrawValue();
			row.addChild(valueText);

			var leftArrow:Sprite = iconButton(ArrowLeftArt, 0.55);
			leftArrow.x = rowW - 46; leftArrow.y = 4;
			row.addChild(leftArrow);

			var rightArrow:Sprite = iconButton(ArrowRightArt, 0.55);
			rightArrow.x = rowW - 22; rightArrow.y = 4;
			row.addChild(rightArrow);

			function cycle(dir:int):void
			{
				var idx:int = 0;
				for (var k:int = 0; k < entry.options.length; k++)
					if (entry.options[k].id == entry.current) { idx = k; break; }
				idx = (idx + dir + entry.options.length) % entry.options.length;
				entry.current = entry.options[idx].id;
				redrawValue();
				applyStyleEntry(entry);
				showDescription(entry);
			}

			leftArrow.addEventListener(MouseEvent.CLICK, function (e:MouseEvent):void { cycle(-1); });
			rightArrow.addEventListener(MouseEvent.CLICK, function (e:MouseEvent):void { cycle(1); });

			row.addEventListener(MouseEvent.MOUSE_OVER, function (e:MouseEvent):void { drawListRowBg(rowBg, rowW, true); showDescription(entry); });
			row.addEventListener(MouseEvent.MOUSE_OUT, function (e:MouseEvent):void { drawListRowBg(rowBg, rowW, false); });

			_listContent.addChild(row);
		}

		// ── "toggle" rows: checkbox control ──────────────────────────────────

		private function addToggleRow(entry:Object, y:Number):void
		{
			var mod:* = Modules.getModule(entry.name);
			var isOn:Boolean = (mod != null && mod.enabled == true);
			var rowW:Number = LEFT_W - 16;

			var row:Sprite = new Sprite();
			row.y = y;
			row.buttonMode = true;

			var rowBg:Shape = new Shape();
			drawListRowBg(rowBg, rowW, false);
			row.addChild(rowBg);

			var label:TextField = new TextField();
			label.autoSize = TextFieldAutoSize.LEFT;
			label.selectable = false;
			label.mouseEnabled = false;
			label.defaultTextFormat = new TextFormat("Arial", 10, COL_TEXT, false);
			label.text = entry.label;
			label.x = 8; label.y = 7;
			row.addChild(label);

			var box:Sprite = new Sprite();
			box.x = rowW - 24; box.y = 6;

			// Both states are forced to the same CHECKBOX_W x CHECKBOX_H
			// footprint (the checked art's native crop isn't the same aspect
			// as the hand-drawn empty box) so toggling doesn't visibly shrink
			// or grow the control.
			function drawBox(on:Boolean):void
			{
				while (box.numChildren > 0) box.removeChildAt(0);
				if (on)
				{
					var check:Bitmap = iconBitmap(CheckboxArt);
					check.width = CHECKBOX_W;
					check.height = CHECKBOX_H;
					box.addChild(check);
				}
				else
				{
					// Stroke is centered on the path by default, so drawing
					// at the full 0,0,W,H bounds would let the line overflow
					// past CHECKBOX_W/H — inset by half the stroke width so
					// the OUTER edge lands exactly on the target footprint.
					var sw:Number = 1.5;
					var empty:Shape = new Shape();
					empty.graphics.lineStyle(sw, COL_BORDER_LO, 1);
					empty.graphics.beginFill(0x000000, 1);
					empty.graphics.drawRoundRect(sw / 2, sw / 2, CHECKBOX_W - sw, CHECKBOX_H - sw, 3, 3);
					empty.graphics.endFill();
					box.addChild(empty);
				}
			}
			drawBox(isOn);
			row.addChild(box);

			row.addEventListener(MouseEvent.MOUSE_OVER, function (e:MouseEvent):void { drawListRowBg(rowBg, rowW, true); showDescription(entry); });
			row.addEventListener(MouseEvent.MOUSE_OUT, function (e:MouseEvent):void { drawListRowBg(rowBg, rowW, false); });

			row.addEventListener(MouseEvent.CLICK, function (e:MouseEvent):void
			{
				try
				{
					var m:* = Modules.getModule(entry.name);
					if (m == null) return;
					if (m.enabled) Modules.disable(entry.name);
					else Modules.enable(entry.name);
					drawBox(m.enabled);
					showDescription(entry);
				}
				catch (err:Error)
				{
					debug("toggle row ERROR (" + entry.name + "): " + err.message);
				}
			});

			_listContent.addChild(row);
		}

		// ── "slider" rows: click-or-drag a track ─────────────────────────────

		private function addSliderRow(entry:Object, y:Number):void
		{
			var rowW:Number = LEFT_W - 16;
			var trackW:Number = rowW - 20;

			var row:Sprite = new Sprite();
			row.y = y;

			var rowBg:Shape = new Shape();
			rowBg.graphics.lineStyle(1, COL_BORDER_LO, 1);
			rowBg.graphics.beginFill(0x000000, 1);
			rowBg.graphics.drawRoundRect(0, 0, rowW, SLIDER_ROW_H - 4, 5, 5);
			rowBg.graphics.endFill();
			row.addChild(rowBg);

			var label:TextField = new TextField();
			label.autoSize = TextFieldAutoSize.LEFT;
			label.selectable = false;
			label.mouseEnabled = false;
			label.defaultTextFormat = new TextFormat("Arial", 10, COL_TEXT, false);
			label.text = entry.label;
			label.x = 10; label.y = 4;
			row.addChild(label);

			var valueText:TextField = new TextField();
			valueText.autoSize = TextFieldAutoSize.LEFT;
			valueText.selectable = false;
			valueText.mouseEnabled = false;
			valueText.defaultTextFormat = new TextFormat("Arial", 10, COL_GOLD, true);
			valueText.text = entry.value + entry.unit;
			valueText.x = rowW - 10 - valueText.textWidth;
			valueText.y = 4;
			row.addChild(valueText);

			var track:Sprite = new Sprite();
			track.x = 10; track.y = 24;
			track.buttonMode = true;

			var trackBg:Shape = new Shape();
			trackBg.graphics.beginFill(COL_OFF, 1);
			trackBg.graphics.drawRoundRect(0, 0, trackW, 5, 5, 5);
			trackBg.graphics.endFill();
			track.addChild(trackBg);

			var frac:Number = (entry.value - entry.min) / (entry.max - entry.min);

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

				valueText.text = entry.value + entry.unit;
				valueText.x = rowW - 10 - valueText.textWidth;
			}

			function applyFromLocalX(localX:Number):void
			{
				var f:Number = Math.max(0, Math.min(1, localX / trackW));
				var raw:Number = entry.min + f * (entry.max - entry.min);
				var stepped:Number = Math.round(raw / entry.step) * entry.step;
				stepped = Math.max(entry.min, Math.min(entry.max, stepped));
				if (stepped == entry.value) return;
				entry.value = stepped;
				redraw((entry.value - entry.min) / (entry.max - entry.min));

				try
				{
					if (entry.needsEnable) Modules.enable(entry.moduleName);
					var mod:* = Modules.getModule(entry.moduleName);
					if (mod) mod[entry.setterName](entry.value);
				}
				catch (err:Error)
				{
					debug("slider ERROR (" + entry.moduleName + "): " + err.message);
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

			row.addEventListener(MouseEvent.MOUSE_OVER, function (e:MouseEvent):void { showDescription(entry); });

			_listContent.addChild(row);
		}

		private function drawListRowBg(shape:Shape, w:Number, hover:Boolean):void
		{
			shape.graphics.clear();
			shape.graphics.beginFill(hover ? COL_ROW_HOVER : 0x000000, 1);
			shape.graphics.drawRect(0, 0, w, ROW_H - 2);
			shape.graphics.endFill();
			shape.graphics.lineStyle(1, 0x1A1A1A, 1);
			shape.graphics.moveTo(0, ROW_H - 2);
			shape.graphics.lineTo(w, ROW_H - 2);
		}
	}
}
