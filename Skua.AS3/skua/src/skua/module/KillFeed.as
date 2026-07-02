package skua.module
{
	import flash.display.GradientType;
	import flash.display.Sprite;
	import flash.display.Stage;
	import flash.geom.Matrix;
	import flash.text.TextField;
	import flash.text.TextFieldAutoSize;
	import flash.text.TextFormat;
	import flash.utils.getTimer;

	public class KillFeed extends Module
	{
		private static const MAX_ENTRIES:int   = 5;
		private static const SHOW_MS:int       = 1500;
		private static const FADE_MS:int       = 500;
		private static const TOTAL_MS:int      = SHOW_MS + FADE_MS;
		private static const TOP_MARGIN:int    = 50;
		private static const RIGHT_MARGIN:int  = 2;
		private static const PAD_X:int         = 8;
		private static const PAD_Y:int         = 5;
		private static const ENTRY_GAP:int     = 3;

		private var _entries:Array;
		private var _prevHP:Object;
		// Running tracker: updated every frame my HP drops, used when I die
		private var _lastAttacker:String;
		private var _myPrevHP:Number;

		private var _overlay:Sprite;

		public function KillFeed() { super("KillFeed"); }

		override public function onToggle(game:*):void
		{
			if (enabled)
			{
				_overlay               = new Sprite();
				_overlay.mouseEnabled  = false;
				_overlay.mouseChildren = false;
				_entries       = [];
				_prevHP        = {};
				_lastAttacker  = "";
				_myPrevHP      = -1;

				try
				{
					var st:Stage = game.stage as Stage;
					st.addChild(_overlay);
				}
				catch (e:Error)
				{
					try { game.parent.addChild(_overlay); } catch (e2:Error) {}
				}
			}
			else
			{
				try { if (_overlay && _overlay.parent) _overlay.parent.removeChild(_overlay); }
				catch (e:Error) {}
				_overlay = null;
				_entries = null;
				_prevHP  = null;
			}
		}

		override public function onFrame(game:*):void
		{
			if (!_overlay) return;
			detectDeaths(game);
			render(game);
		}

		// ── death detection ───────────────────────────────────────────────────
		private function detectDeaths(game:*):void
		{
			var myName:String = "";
			try { myName = String(game.world.myAvatar.objData.strUsername); } catch (e:Error) {}
			var myFrame:String = "";
			try { myFrame = String(game.world.strFrame).toLowerCase(); } catch (e:Error) {}

			// Track who's hurting me in real time (frame-by-frame HP drop).
			// This avoids scanning all avatars at death time, which picks up
			// PvP NPCs (e.g. "Team A Captain") sitting in other cells.
			var myHP:Number = 0;
			try { myHP = Number(game.world.myAvatar.dataLeaf.intHP); } catch (e:Error) {}
			if (_myPrevHP > 0 && myHP > 0 && myHP < _myPrevHP)
				updateLastAttacker(game, myFrame);
			_myPrevHP = myHP;

			// ── Avatars ───────────────────────────────────────────────────────
			try
			{
				for (var avid:* in game.world.avatars)
				{
					var av:* = game.world.avatars[avid];
					if (!av) continue;
					var aKey:String = "a_" + String(avid);
					var hp:Number   = 0;
					try { hp = Number(av.dataLeaf.intHP); } catch (e:Error) {}

					if (_prevHP[aKey] !== undefined && Number(_prevHP[aKey]) > 0 && hp <= 0)
					{
						var isMe:Boolean = false;
						try { isMe = Boolean(av.isMyAvatar); } catch (e:Error) {}

						var victimName:String = isMe ? myName : safeStr(av, "objData.strUsername");
						if (!valid(victimName)) victimName = "Unknown";

						var killerName:String = "";
						if (isMe)
						{
							// Use the attacker tracked while my HP was dropping
							killerName = _lastAttacker;

							// If nothing tracked yet, fall back to any monster in room
							if (!valid(killerName))
							{
								try
								{
									for (var midX:* in game.world.monsters)
									{
										var monX:* = game.world.monsters[midX];
										if (!monX) continue;
										var mnX:String = monName(monX);
										if (valid(mnX)) { killerName = mnX; break; }
									}
								}
								catch (e3:Error) {}
							}

							// Reset so respawn HP spike doesn't carry over
							_lastAttacker = "";
							_myPrevHP     = -1;
						}
						else
						{
							// Someone else died — credit me unless confirmed teammate
							var victimLc:String = "";
							try { victimLc = String(av.objData.strUsername).toLowerCase(); } catch (e:Error) {}
							killerName = TeammateRoster.isTeammate(victimLc) ? "Unknown" : (valid(myName) ? myName : "Unknown");
						}

						push(valid(killerName) ? killerName : "Unknown", victimName);
					}
					_prevHP[aKey] = hp;
				}
			}
			catch (e:Error) {}

			// ── Monsters ──────────────────────────────────────────────────────
			try
			{
				for (var mid:* in game.world.monsters)
				{
					var mon:* = game.world.monsters[mid];
					if (!mon) continue;
					var mKey:String = "m_" + String(mid);
					var mhp:Number  = 0;
					try { mhp = Number(mon.dataLeaf.intHP); } catch (e:Error) {}

					if (_prevHP[mKey] !== undefined && Number(_prevHP[mKey]) > 0 && mhp <= 0)
					{
						push(valid(myName) ? myName : "Unknown", monName(mon) || "Monster");
					}
					_prevHP[mKey] = mhp;
				}
			}
			catch (e:Error) {}
		}

		// Called every frame my HP drops. Records who is in MY current cell and
		// on the enemy team — real players only (via areaUsers), then monsters,
		// then any enemy as a last resort. Cell filter is the key guard against
		// PvP captain NPCs who sit in their base room.
		private function updateLastAttacker(game:*, myFrame:String):void
		{
			// Build real-player whitelist from areaUsers
			var realSet:Object = {};
			var hasReal:Boolean = false;
			try
			{
				for (var uid:* in game.world.areaUsers)
				{
					var u:* = game.world.areaUsers[uid];
					if (!u) continue;
					var un:String = "";
					try { un = String(u.objData ? u.objData.strUsername : u.strUsername).toLowerCase(); }
					catch (e:Error) {}
					if (valid(un)) { realSet[un] = true; hasReal = true; }
				}
			}
			catch (e:Error) {}

			// Pass 1 — real players (in areaUsers) in MY cell on enemy team
			try
			{
				for (var avid:* in game.world.avatars)
				{
					var av:* = game.world.avatars[avid];
					if (!av || av.isMyAvatar) continue;

					var n:String = safeStr(av, "objData.strUsername");
					if (!valid(n)) continue;
					if (hasReal && !realSet[n.toLowerCase()]) continue; // skip NPCs

					var theirFrame:String = "";
					try { theirFrame = String(av.objData.strFrame).toLowerCase(); } catch (e:Error) {}
					if (valid(myFrame) && valid(theirFrame) && theirFrame != myFrame) continue;

					if (TeammateRoster.isTeammate(n.toLowerCase())) continue;

					_lastAttacker = n;
					return;
				}
			}
			catch (e:Error) {}

			// Pass 2 — monsters (always in current room)
			try
			{
				for (var mid:* in game.world.monsters)
				{
					var mon:* = game.world.monsters[mid];
					if (!mon) continue;
					var mn:String = monName(mon);
					if (valid(mn)) { _lastAttacker = mn; return; }
				}
			}
			catch (e:Error) {}

			// Pass 3 — any enemy in my cell (fallback, no areaUsers filter)
			try
			{
				for (var avid2:* in game.world.avatars)
				{
					var av2:* = game.world.avatars[avid2];
					if (!av2 || av2.isMyAvatar) continue;

					var theirFrame2:String = "";
					try { theirFrame2 = String(av2.objData.strFrame).toLowerCase(); } catch (e:Error) {}
					if (valid(myFrame) && valid(theirFrame2) && theirFrame2 != myFrame) continue;

					var n2Lc:String = safeStr(av2, "objData.strUsername").toLowerCase();
					if (TeammateRoster.isTeammate(n2Lc)) continue;

					var n2:String = safeStr(av2, "objData.strUsername");
					if (valid(n2)) { _lastAttacker = n2; return; }
				}
			}
			catch (e:Error) {}
		}

		// ── entry management ─────────────────────────────────────────────────
		private function push(killer:String, victim:String):void
		{
			if (!valid(killer)) killer = "Unknown";
			if (!valid(victim)) victim = "Unknown";
			_entries.unshift({ killer: killer, victim: victim, time: getTimer() });
			if (_entries.length > MAX_ENTRIES) _entries.length = MAX_ENTRIES;
		}

		// ── rendering ────────────────────────────────────────────────────────
		private function render(game:*):void
		{
			while (_overlay.numChildren > 0) _overlay.removeChildAt(0);

			var now:int    = getTimer();
			var stageW:int = 800;
			try { stageW = int(game.stage.stageWidth); } catch (e:Error) {}

			for (var i:int = _entries.length - 1; i >= 0; i--)
				if (now - int(_entries[i].time) >= TOTAL_MS) _entries.splice(i, 1);

			var yOff:Number = TOP_MARGIN;

			for (var j:int = 0; j < _entries.length; j++)
			{
				var entry:Object = _entries[j];
				var age:int      = now - int(entry.time);
				var alpha:Number = age <= SHOW_MS ? 1.0
				                 : 1.0 - (age - SHOW_MS) / Number(FADE_MS);
				alpha = Math.max(0, Math.min(1, alpha));

				var html:String =
					"<font color='#E8C870'><b>" + xmlEsc(entry.killer) + "</b></font>" +
					"<font color='#4A6080'> eliminated </font>" +
					"<font color='#E06060'><b>" + xmlEsc(entry.victim) + "</b></font>";

				var fmt:TextFormat = new TextFormat("Arial", 11, 0xE8C870, false);
				var tf:TextField   = new TextField();
				tf.defaultTextFormat = fmt;
				tf.autoSize     = TextFieldAutoSize.LEFT;
				tf.selectable   = false;
				tf.mouseEnabled = false;
				tf.multiline    = false;
				tf.htmlText     = html;

				// Add field first so autoSize resolves before we measure
				var sp:Sprite = new Sprite();
				tf.x = 3 + PAD_X;
				tf.y = PAD_Y;
				sp.addChild(tf);

				var entW:Number = tf.width  + PAD_X * 2 + 4;
				var entH:Number = tf.height + PAD_Y * 2;

				// Draw background AFTER measuring (addChild resolved autoSize)
				var gm:Matrix = new Matrix();
				gm.createGradientBox(entW, entH, Math.PI * 0.5, 0, 0);
				sp.graphics.beginGradientFill(GradientType.LINEAR,
					[0x0D1E36, 0x060A14], [0.93, 0.93], [0, 255], gm);
				sp.graphics.drawRoundRect(0, 0, entW, entH, 4, 4);
				sp.graphics.endFill();
				// Gold left accent bar
				sp.graphics.beginFill(0xC8A040, 0.85);
				sp.graphics.drawRoundRect(0, 0, 3, entH, 2, 2);
				sp.graphics.endFill();
				// Thin gold border
				sp.graphics.lineStyle(1, 0xC8A040, 0.35);
				sp.graphics.drawRoundRect(0, 0, entW, entH, 4, 4);

				// Push tf back to top of display stack (drawn after background)
				sp.addChild(tf);

				sp.x     = stageW - entW - RIGHT_MARGIN;
				sp.y     = yOff;
				sp.alpha = alpha;
				_overlay.addChild(sp);
				yOff += entH + ENTRY_GAP;
			}
		}

		// ── helpers ──────────────────────────────────────────────────────────
		private function safeStr(obj:*, path:String):String
		{
			try
			{
				var parts:Array = path.split(".");
				var cur:* = obj;
				for each (var p:String in parts) cur = cur[p];
				var s:String = String(cur);
				return valid(s) ? s : "";
			}
			catch (e:Error) {}
			return "";
		}

		private function monName(mon:*):String
		{
			var s:String = "";
			try { s = String(mon.strMonName); }         catch (e:Error) {}
			if (valid(s)) return s;
			try { s = String(mon.objData.strMonName); } catch (e:Error) {}
			if (valid(s)) return s;
			return "";
		}

		private function valid(s:String):Boolean
		{
			return s != null && s.length > 0 && s != "undefined" && s != "null";
		}

		private function xmlEsc(s:String):String
		{
			return s.replace(/&/g, "&amp;")
			        .replace(/</g, "&lt;")
			        .replace(/>/g, "&gt;");
		}
	}
}
