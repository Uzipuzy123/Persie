package skua.module
{
	import flash.text.TextField;
	import flash.text.TextFormat;
	import flash.utils.Dictionary;
	import flash.filters.GlowFilter;
	import flash.filters.DropShadowFilter;

	/**
	 * Overrides every avatar's floating nameplate font — pMC.pname.ti (the
	 * username, e.g. "uzair") and pMC.pname.tg (the guild/title line below
	 * it, e.g. "The One") — real, live, per-avatar TextFields confirmed via
	 * a DebugPanel dump of a real pname instance. An earlier attempt used
	 * pMC.pname.typ instead, going off a decompiled reference to the game's
	 * own "applyComicSansPname" feature — that turned out to be a
	 * conditional race-label ("< Race >") that's usually absent/invisible,
	 * not the actual name text, which is why nothing visibly changed.
	 *
	 * Reversible the same way other text restyles in this codebase are: each
	 * TextField's original TextFormat is saved (dynamic property) before the
	 * first override, restored when the selection goes back to "Off" (id 0)
	 * or the module is disabled. Only .font is changed — size/color/
	 * bold/italic/underline are carried over from the original format.
	 */
	public class NameplateFont extends Module
	{
		// Picked for visual variety, not just "a different font" — most Windows
		// fonts read as generic sans/serif at nameplate size, so this favors
		// styles that are structurally different from their neighbors (blocky
		// vs script vs monospace vs ornate) over another plain system font.
		private static const FONTS:Array = [
			null,               // 0  = Off — never applied, just restores original
			"Comic Sans MS",    // 1  — casual rounded handwriting
			"Impact",           // 2  — bold condensed headline
			"Papyrus",          // 3  — textured decorative serif
			"Arial Black",      // 4  — ultra-bold heavy sans
			"Consolas",         // 5  — monospace
			"Segoe Script",     // 6  — flowing cursive
			"Gabriola",         // 7  — ornate calligraphic
			"MV Boli",          // 8  — quirky rounded doodle
			"Bahnschrift",      // 9  — geometric futuristic
			"Ink Free",         // 10 — natural handwriting scrawl
			"Constantia",       // 11 — Golden Royalty (elegant serif)
			"Sylfaen",          // 12 — Ancient Blood (old-style serif)
			"Candara",          // 13 — Toxic Glow (soft humanist sans)
			"Corbel",           // 14 — Frostbite (thin elegant sans)
			"Malgun Gothic"     // 15 — Cyber Pink (crisp minimal sans)
		];

		// -1 = keep the nameplate's own original color; only the last 5 "themed"
		// entries recolor the text to match their glow.
		private static const COLORS:Array = [
			-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
			0xFFD700, // 11 Golden Royalty
			0xCC1010, // 12 Ancient Blood
			0x39FF14, // 13 Toxic Glow
			0x66E0FF, // 14 Frostbite
			0xFF2FD8  // 15 Cyber Pink
		];

		private var _fontId:int = 0;
		private var _logged:Boolean = false;

		// TextField is a sealed class — it can't hold dynamic properties like
		// __skuaOrigFormat directly (throws ReferenceError #1069), so original
		// formats/applied-state are tracked here instead, keyed by field instance.
		private var _origFormats:Dictionary = new Dictionary(true);
		private var _origEmbedFonts:Dictionary = new Dictionary(true);
		private var _origFilters:Dictionary = new Dictionary(true);
		private var _applied:Dictionary = new Dictionary(true);

		public function NameplateFont() { super("NameplateFont"); }

		public function setFont(id:int):void
		{
			_fontId = id;
			_logged = false;
			_frameLogged = false;
			DebugPanel.append("[NameplateFont] setFont(" + id + ") called — enabled=" + enabled);
		}

		override public function onToggle(game:*):void
		{
			DebugPanel.append("[NameplateFont] onToggle — enabled=" + enabled);
			if (!enabled) restoreAll(game);
		}

		private var _frameLogged:Boolean = false;

		override public function onFrame(game:*):void
		{
			if (!_frameLogged)
			{
				_frameLogged = true;
				var avCount:int = 0;
				try { for (var k:* in game.world.avatars) avCount++; } catch (ce:Error) {}
				DebugPanel.append("[NameplateFont] onFrame — enabled=" + enabled + " fontId=" + _fontId + " avatarCount=" + avCount);
			}
			if (!enabled) return;
			try
			{
				for (var aid:* in game.world.avatars)
					applyToAvatar(game.world.avatars[aid]);
			}
			catch (e:Error) {}
		}

		private function applyToAvatar(av:*):void
		{
			var isSelf:Boolean = false;
			try { isSelf = av.isMyAvatar; } catch (ie:Error) {}

			if (isSelf && !_logged)
			{
				try
				{
					DebugPanel.append("[NameplateFont] self avatar: av=" + (av != null) +
						" pMC=" + (av && av.pMC != null) +
						" pname=" + (av && av.pMC && av.pMC.pname != null) +
						" ti=" + (av && av.pMC && av.pMC.pname && av.pMC.pname.ti != null) +
						" tiIsTextField=" + (av && av.pMC && av.pMC.pname && (av.pMC.pname.ti is TextField)) +
						" tg=" + (av && av.pMC && av.pMC.pname && av.pMC.pname.tg != null));
				}
				catch (le:Error) { DebugPanel.append("[NameplateFont] self-avatar diag FAILED: " + le.message); }
			}

			try
			{
				if (!av || !av.pMC || !av.pMC.pname) return;
				applyToField(av.pMC.pname.ti as TextField);
				applyToField(av.pMC.pname.tg as TextField);
			}
			catch (e:Error)
			{
				if (isSelf) DebugPanel.append("[NameplateFont] applyToAvatar FAILED: " + e.message);
			}
		}

		private function applyToField(tf:TextField):void
		{
			if (!tf) return;
			try
			{
				if (_origFormats[tf] == null)
				{
					_origFormats[tf] = tf.getTextFormat();
					_origEmbedFonts[tf] = tf.embedFonts;
					_origFilters[tf] = tf.filters;
				}

				if (_fontId <= 0 || _fontId >= FONTS.length)
				{
					if (_applied[tf])
					{
						var orig:TextFormat = _origFormats[tf] as TextFormat;
						tf.embedFonts = _origEmbedFonts[tf] as Boolean;
						tf.filters = _origFilters[tf] as Array;
						tf.defaultTextFormat = orig;
						tf.setTextFormat(orig);
						_applied[tf] = false;
					}
					return;
				}

				var base:TextFormat = _origFormats[tf] as TextFormat;
				var fmt:TextFormat = new TextFormat();
				fmt.font      = FONTS[_fontId];
				fmt.size      = base.size;
				fmt.color     = COLORS[_fontId] == -1 ? base.color : COLORS[_fontId];
				fmt.bold      = base.bold;
				fmt.italic    = base.italic;
				fmt.underline = base.underline;

				// The field may default to embedFonts=true (the game embeds its own
				// font for nameplates) — in that mode Flash ONLY renders fonts it
				// finds already embedded under that exact name, never falling back
				// to a device/system font, so most of our picks would render blank.
				// Force device-font lookup for whatever we explicitly choose here.
				tf.embedFonts = false;
				tf.defaultTextFormat = fmt;
				tf.setTextFormat(fmt);
				tf.filters = buildFilters(_fontId);
				_applied[tf] = true;

				if (!_logged)
				{
					_logged = true;
					var readBack:TextFormat = tf.getTextFormat();
					DebugPanel.append("[NameplateFont] text=\"" + tf.text + "\" embedFonts=" + tf.embedFonts +
						" antiAliasType=" + tf.antiAliasType + " wantedFont=" + fmt.font +
						" readBackFont=" + readBack.font);
				}
			}
			catch (e:Error) { DebugPanel.append("[NameplateFont] applyToField FAILED on \"" + tf.text + "\": " + e.message); }
		}

		// Only the 5 "themed" entries (11+) get a glow — every earlier entry is a
		// plain font swap with no filters, same as before this was added.
		private function buildFilters(id:int):Array
		{
			switch (id)
			{
				case 11: // Golden Royalty
					return [new GlowFilter(0xFFAA00, 0.9, 8, 8, 3, 2), new DropShadowFilter(2, 45, 0x000000, 0.6, 3, 3, 1, 2)];
				case 12: // Ancient Blood
					return [new GlowFilter(0xFF0000, 0.85, 8, 8, 3, 2), new DropShadowFilter(2, 45, 0x000000, 0.7, 4, 4, 1, 2)];
				case 13: // Toxic Glow
					return [new GlowFilter(0x22FF00, 0.9, 10, 10, 4, 2)];
				case 14: // Frostbite
					return [new GlowFilter(0x00CCFF, 0.9, 10, 10, 3, 2)];
				case 15: // Cyber Pink
					return [new GlowFilter(0xFF00CC, 0.9, 10, 10, 4, 2)];
				default:
					return [];
			}
		}

		private function restoreAll(game:*):void
		{
			try
			{
				for (var aid:* in game.world.avatars)
					restoreAvatar(game.world.avatars[aid]);
			}
			catch (e:Error) {}
		}

		private function restoreAvatar(av:*):void
		{
			try
			{
				if (!av || !av.pMC || !av.pMC.pname) return;
				restoreField(av.pMC.pname.ti as TextField);
				restoreField(av.pMC.pname.tg as TextField);
			}
			catch (e:Error) {}
		}

		private function restoreField(tf:TextField):void
		{
			if (!tf) return;
			try
			{
				var orig:* = _origFormats[tf];
				if (orig != null)
				{
					tf.embedFonts = _origEmbedFonts[tf] as Boolean;
					tf.filters = _origFilters[tf] as Array;
					tf.defaultTextFormat = orig;
					tf.setTextFormat(orig);
				}
				_origFormats[tf] = null;
				_origEmbedFonts[tf] = null;
				_origFilters[tf] = null;
				_applied[tf] = false;
			}
			catch (e:Error) {}
		}
	}
}
