package skua.module
{
	import flash.display.GradientType;
	import flash.display.Sprite;
	import flash.display.Stage;
	import flash.events.KeyboardEvent;
	import flash.geom.Matrix;
	import flash.text.TextField;
	import flash.text.TextFieldAutoSize;
	import flash.text.TextFormat;

	public class ScoreboardOverlay extends Module
	{
		private static const KEY_TAB:uint    = 9;
		private static const PANEL_W:int     = 640;
		private static const TITLE_H:int     = 20;
		private static const COL_HDR_H:int   = 18;
		private static const ROW_H:int       = 17;
		private static const SIDE_PAD:int    = 6;

		// Column widths per side — must sum to PANEL_W/2 - SIDE_PAD - 2 = 312
		private static const COL_NAME:int = 130;
		private static const COL_K:int    = 30;
		private static const COL_D:int    = 30;
		private static const COL_DMG:int  = 60;
		private static const COL_HLG:int  = 62;

		// Y offsets in overlay-local space
		private static const TITLE_Y:int  = 3;
		private static const HDR_Y:int    = 27;   // TITLE_Y + TITLE_H + 4
		private static const ROWS_Y:int   = 45;   // HDR_Y + COL_HDR_H

		private static const GOLD:uint          = 0xC8A040;
		private static const TEAM_A_COLOR:uint  = 0x2ECC71;
		private static const TEAM_B_COLOR:uint  = 0xE05050;

		// ── state ─────────────────────────────────────────────────────────────
		private var _overlay:Sprite;
		private var _stage:Stage;
		private var _visible:Boolean;

		private var _stats:Object;         // lc username → stat row object
		private var _prevHP:Object;        // lc username → last HP value
		private var _lastAttacker:Object;  // lc victim   → attacker display name
		private var _cachedMyTeam:String = "";

		public function ScoreboardOverlay() { super("ScoreboardOverlay"); }

		// ── lifecycle ─────────────────────────────────────────────────────────
		override public function onToggle(game:*):void
		{
			if (enabled)
			{
				_overlay  = new Sprite();
				_stats    = {};
				_prevHP   = {};
				_lastAttacker = {};
				_visible  = false;

				_overlay.visible       = false;
				_overlay.mouseEnabled  = false;
				_overlay.mouseChildren = false;

				try
				{
					_stage = game.stage as Stage;
					_stage.addChild(_overlay);
					_stage.addEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
					_stage.addEventListener(KeyboardEvent.KEY_UP,   onKeyUp);
				}
				catch (e:Error)
				{
					try { game.parent.addChild(_overlay); } catch (e2:Error) {}
				}
			}
			else
			{
				try
				{
					if (_stage)
					{
						_stage.removeEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
						_stage.removeEventListener(KeyboardEvent.KEY_UP,   onKeyUp);
					}
				}
				catch (e:Error) {}

				try { if (_overlay && _overlay.parent) _overlay.parent.removeChild(_overlay); }
				catch (e:Error) {}

				_overlay      = null;
				_stats        = null;
				_prevHP       = null;
				_lastAttacker = null;
				_cachedMyTeam = "";
				_stage        = null;
			}
		}

		override public function onFrame(game:*):void
		{
			if (!_overlay) return;
			trackStats(game);
			if (_visible) render(game);
		}

		// ── keyboard ──────────────────────────────────────────────────────────
		private function onKeyDown(e:KeyboardEvent):void
		{
			if (e.keyCode == KEY_TAB)
			{
				_visible = true;
				_overlay.visible = true;
				e.preventDefault();
			}
		}

		private function onKeyUp(e:KeyboardEvent):void
		{
			if (e.keyCode == KEY_TAB)
			{
				_visible = false;
				_overlay.visible = false;
			}
		}

		// ── stat tracking ─────────────────────────────────────────────────────
		private function trackStats(game:*):void
		{
			var myName:String = "";
			try { myName = String(game.world.myAvatar.objData.strUsername); } catch (e:Error) {}
			var myTeam:* = null;
			try { myTeam = game.world.myAvatar.objData.strTeam; } catch (e:Error) {}
			var myFrame:String = "";
			try { myFrame = String(game.world.strFrame).toLowerCase(); } catch (e:Error) {}

			// Cache team so it survives the null window that occurs when we die
			var myTeamLive:String = (myTeam != null && String(myTeam) != "undefined" && String(myTeam) != "") ? String(myTeam) : "";
			if (myTeamLive.length > 0) _cachedMyTeam = myTeamLive;

			// Seed entries for every player in the room so enemies show immediately,
			// even before they enter combat range (avatars dict may not have their name yet)
			try
			{
				for (var uid:* in game.world.areaUsers)
				{
					var user:* = game.world.areaUsers[uid];
					if (!user) continue;
					var uIsMe:Boolean = false;
					try { uIsMe = Boolean(user.isMyAvatar); } catch (eu:Error) {}
					if (uIsMe) continue;
					var uName:String = "";
					try { uName = String(user.objData ? user.objData.strUsername : user.strUsername); } catch (eu2:Error) {}
					if (!valid(uName)) continue;
					var uKey:String = uName.toLowerCase();
					if (_stats[uKey]) continue; // already tracked
					_stats[uKey] = mkRow(uName, null, false); // team resolved by avatars loop via objData.strTeam
				}
			}
			catch (eu4:Error) {}

			try
			{
				for (var avid:* in game.world.avatars)
				{
					var av:* = game.world.avatars[avid];
					if (!av) continue;

					var isMe:Boolean = false;
					try { isMe = Boolean(av.isMyAvatar); } catch (e:Error) {}

					var aName:String = isMe ? myName : "";
					if (!isMe)
					{
						try { aName = String(av.objData.strUsername); } catch (e:Error) {}
						if (!valid(aName)) try { aName = String(av.strUsername); } catch (e2:Error) {}
					}
					if (!valid(aName)) continue;

					var aKey:String = aName.toLowerCase();
					// Own avatar's strTeam is only reliable on game.world.myAvatar,
					// not on the entry inside game.world.avatars — use myTeam directly.
					var aTeam:* = isMe ? myTeam : null;
					if (!isMe) try { aTeam = av.objData.strTeam; } catch (e:Error) {}

					if (!_stats[aKey])
						_stats[aKey] = mkRow(aName, aTeam, isMe);
					else
					{
						// Avatars-loop team (objData.strTeam) is authoritative — always overwrite
						if (aTeam != null) _stats[aKey].team = aTeam;
						if (isMe) _stats[aKey].isMe = true;
					}

					var curHP:Number = 0;
					try { curHP = Number(av.dataLeaf.intHP); } catch (e:Error) {}

					if (_prevHP[aKey] !== undefined)
					{
						var prevHP:Number = Number(_prevHP[aKey]);
						var delta:Number  = curHP - prevHP;

						if (delta < 0 && prevHP > 0)
						{
							var dmg:Number = -delta;
							var avFrame:String = isMe ? myFrame : frameOf(av);
							var atk:String = findAttacker(game, aKey, aTeam, avFrame, myName, myTeam);
							if (valid(atk))
							{
								_lastAttacker[aKey] = atk;
								var atkKey:String = atk.toLowerCase();
								if (!_stats[atkKey]) _stats[atkKey] = mkRow(atk, null);
								_stats[atkKey].dealt += dmg;
							}

							if (curHP <= 0)
							{
								_stats[aKey].deaths++;
								var killer:String = _lastAttacker[aKey];
								if (valid(killer))
								{
									var kKey:String = killer.toLowerCase();
									if (!_stats[kKey]) _stats[kKey] = mkRow(killer, null);
									_stats[kKey].kills++;
								}
								_lastAttacker[aKey] = "";
							}
						}
						else if (delta > 0 && prevHP > 0)
						{
							_stats[aKey].healing += delta;
						}
					}

					_prevHP[aKey] = curHP;
				}
			}
			catch (e:Error) {}
		}

		// Find the most likely attacker: opposite-team player in the same cell.
		private function findAttacker(game:*, victimKey:String, victimTeam:*,
		                              victimFrame:String, myName:String, myTeam:*):String
		{
			try
			{
				for (var avid:* in game.world.avatars)
				{
					var av:* = game.world.avatars[avid];
					if (!av) continue;

					var isMe:Boolean = false;
					try { isMe = Boolean(av.isMyAvatar); } catch (e:Error) {}

					var n:String = isMe ? myName : "";
					if (!isMe) try { n = String(av.objData.strUsername); } catch (e:Error) {}
					if (!valid(n) || n.toLowerCase() == victimKey) continue;

					var aTeam:* = null;
					try { aTeam = av.objData.strTeam; } catch (e:Error) {}
					if (victimTeam != null && aTeam != null &&
					    String(victimTeam) == String(aTeam)) continue;

					var aFrame:String = isMe
					    ? String(game.world.strFrame).toLowerCase()
					    : frameOf(av);
					if (valid(victimFrame) && valid(aFrame) && aFrame != victimFrame) continue;

					return n;
				}
			}
			catch (e:Error) {}
			return "";
		}

		// ── rendering ─────────────────────────────────────────────────────────
		private function render(game:*):void
		{
			while (_overlay.numChildren > 0) _overlay.removeChildAt(0);

			var myTeam:* = null;
			try { myTeam = game.world.myAvatar.objData.strTeam; } catch (e:Error) {}
			var myName:String = "";
			try { myName = String(game.world.myAvatar.objData.strUsername); } catch (e:Error) {}
			var myTeamStr:String = (myTeam != null && String(myTeam) != "undefined" && String(myTeam) != "") ? String(myTeam) : _cachedMyTeam;

			var stageW:int = 800;
			var stageH:int = 600;
			try { stageW = int(game.stage.stageWidth);  } catch (e:Error) {}
			try { stageH = int(game.stage.stageHeight); } catch (e:Error) {}

			var teamA:Array = [];
			var teamB:Array = [];
			for (var k:String in _stats)
			{
				var s:Object = _stats[k];
				if (!valid(s.name)) continue;

				// Self is always on my side
				if (s.isMe) { teamA.push(s); continue; }

				// If we don't know our own team yet, skip — we can't sort correctly
				if (myTeamStr.length == 0) continue;

				// Known team: match = ally, mismatch or unknown = enemy
				var ts:String = (s.team != null && String(s.team) != "undefined" && String(s.team) != "") ? String(s.team) : "";
				if (ts.length > 0 && ts == myTeamStr) teamA.push(s);
				else teamB.push(s);
			}
			teamA.sort(byKills);
			teamB.sort(byKills);

			var maxRows:int = Math.max(teamA.length, teamB.length, 1);
			var panelH:int  = ROWS_Y + maxRows * ROW_H + SIDE_PAD + 4;

			_overlay.x = int((stageW - PANEL_W) * 0.5);
			_overlay.y = int((stageH - panelH)  * 0.38);

			drawBg(panelH);
			drawSide(teamA, true,  panelH, myName.toLowerCase());
			drawSide(teamB, false, panelH, "");
		}

		private function drawBg(panelH:int):void
		{
			var sp:Sprite = new Sprite();
			var m:Matrix  = new Matrix();
			var w:int = PANEL_W;
			var h:int = panelH;

			// Outer gold frame
			m.createGradientBox(w, h, Math.PI * 0.5, 0, 0);
			sp.graphics.beginGradientFill(GradientType.LINEAR,
				[0x9A7230, 0x3D2808], [1, 1], [0, 255], m);
			sp.graphics.drawRoundRect(0, 0, w, h, 6, 6);
			sp.graphics.endFill();

			// Inner navy panel
			m.createGradientBox(w-4, h-4, Math.PI * 0.5, 2, 2);
			sp.graphics.beginGradientFill(GradientType.LINEAR,
				[0x0D1E36, 0x060A14], [0.96, 0.96], [0, 255], m);
			sp.graphics.drawRoundRect(2, 2, w-4, h-4, 5, 5);
			sp.graphics.endFill();

			// Gold inner border
			sp.graphics.lineStyle(1, GOLD, 0.42);
			sp.graphics.drawRoundRect(2, 2, w-4, h-4, 5, 5);

			// Title strip
			m.createGradientBox(w-6, TITLE_H + 2, Math.PI * 0.5, 3, TITLE_Y);
			sp.graphics.beginGradientFill(GradientType.LINEAR,
				[0x1C3050, 0x0A1628], [1, 1], [0, 255], m);
			sp.graphics.drawRect(3, TITLE_Y, w-6, TITLE_H + 2);
			sp.graphics.endFill();

			// Title strip divider
			sp.graphics.lineStyle(1, GOLD, 0.28);
			sp.graphics.moveTo(4, HDR_Y - 2);
			sp.graphics.lineTo(w-4, HDR_Y - 2);

			// Center column divider
			var cx:int = w / 2;
			sp.graphics.lineStyle(1, GOLD, 0.18);
			sp.graphics.moveTo(cx, HDR_Y);
			sp.graphics.lineTo(cx, h - 4);

			_overlay.addChild(sp);

			// "SCOREBOARD" title
			var title:TextField = mkLabel("SCOREBOARD", 10, 0xE8C870, true);
			title.x = int((w - title.width) * 0.5);
			title.y = TITLE_Y + int((TITLE_H - title.height) * 0.5) + 1;
			_overlay.addChild(title);

			// "HOLD TAB" hint
			var hint:TextField = mkLabel("HOLD TAB", 7, 0x3A5070, false);
			hint.x = w - hint.width - 6;
			hint.y = TITLE_Y + int((TITLE_H - hint.height) * 0.5) + 1;
			_overlay.addChild(hint);
		}

		private function drawSide(players:Array, isLeft:Boolean,
		                          panelH:int, hlName:String):void
		{
			var teamColor:uint = isLeft ? TEAM_A_COLOR : TEAM_B_COLOR;
			var accentBg:uint  = isLeft ? 0x0C2010 : 0x200C0C;
			var sideX:int      = isLeft ? SIDE_PAD : PANEL_W / 2 + 2;
			var sideW:int      = PANEL_W / 2 - SIDE_PAD - 2;

			// Team header row background
			var hdrBg:Sprite = new Sprite();
			hdrBg.graphics.beginFill(accentBg, 0.70);
			hdrBg.graphics.drawRect(sideX, HDR_Y, sideW, COL_HDR_H);
			hdrBg.graphics.endFill();
			_overlay.addChild(hdrBg);

			// Team label
			var teamLbl:String   = isLeft ? "OUR TEAM" : "ENEMY TEAM";
			var tl:TextField     = mkLabel(teamLbl, 8, teamColor, true);
			tl.x = sideX + 3;
			tl.y = HDR_Y + int((COL_HDR_H - tl.height) * 0.5);
			_overlay.addChild(tl);

			// Column headers (K D DMG HEAL) — right-aligned in each slot
			var colHdrs:Array  = ["K", "D", "DMG", "HEAL"];
			var colWidths:Array = [COL_K, COL_D, COL_DMG, COL_HLG];
			var hx:int = sideX + COL_NAME;
			for (var ci:int = 0; ci < colHdrs.length; ci++)
			{
				var ch:TextField = mkLabel(String(colHdrs[ci]), 8, 0x5A7A9A, true);
				ch.x = hx + int(colWidths[ci]) - ch.width - 3;
				ch.y = HDR_Y + int((COL_HDR_H - ch.height) * 0.5);
				_overlay.addChild(ch);
				hx += int(colWidths[ci]);
			}

			// Player rows
			for (var i:int = 0; i < players.length; i++)
			{
				var p:Object     = players[i];
				var ry:int       = ROWS_Y + i * ROW_H;
				var isHL:Boolean = p.name.toLowerCase() == hlName;

				// Row background: highlighted (me) or zebra
				if (isHL)
				{
					var hlSp:Sprite = new Sprite();
					hlSp.graphics.beginFill(isLeft ? 0x103818 : 0x381018, 0.50);
					hlSp.graphics.drawRect(sideX, ry, sideW, ROW_H);
					hlSp.graphics.endFill();
					_overlay.addChild(hlSp);
				}
				else if (i % 2 == 1)
				{
					var zSp:Sprite = new Sprite();
					zSp.graphics.beginFill(0x080F1C, 0.25);
					zSp.graphics.drawRect(sideX, ry, sideW, ROW_H);
					zSp.graphics.endFill();
					_overlay.addChild(zSp);
				}

				var nc:uint = isHL ? 0xE8C870 : 0xB0C0D0;
				var vy:int  = ry + 3;

				// Name (clip if overflows)
				var ntf:TextField = mkLabel(p.name, 9, nc, isHL);
				if (ntf.width > COL_NAME - 4) ntf.width = COL_NAME - 4;
				ntf.x = sideX + 3;
				ntf.y = vy;
				_overlay.addChild(ntf);

				// Stat values
				var vals:Array   = [p.kills, p.deaths, fmtNum(p.dealt), fmtNum(p.healing)];
				var colors:Array = [
					p.kills  > 0 ? 0x6ADF6A : 0x506070,
					p.deaths > 0 ? 0xDF6A6A : 0x506070,
					0x7ABACC,
					0x5AA0D0
				];
				var vx:int     = sideX + COL_NAME;
				var vws:Array  = [COL_K, COL_D, COL_DMG, COL_HLG];
				for (var vi:int = 0; vi < vals.length; vi++)
				{
					var vtf:TextField = mkLabel(String(vals[vi]), 9, uint(colors[vi]), false);
					vtf.x = vx + int(vws[vi]) - vtf.width - 3;
					vtf.y = vy;
					_overlay.addChild(vtf);
					vx += int(vws[vi]);
				}
			}
		}

		// ── helpers ───────────────────────────────────────────────────────────
		private function mkRow(name:String, team:*, isMe:Boolean = false):Object
		{
			return { name: name, team: team, isMe: isMe, kills: 0, deaths: 0, dealt: 0, healing: 0 };
		}

		private function frameOf(av:*):String
		{
			try { return String(av.objData.strFrame).toLowerCase(); } catch (e:Error) {}
			try { return String(av.strFrame).toLowerCase(); }         catch (e:Error) {}
			return "";
		}

		private function byKills(a:Object, b:Object):int
		{
			return int(b.kills) - int(a.kills);
		}

		private function fmtNum(n:Number):String
		{
			var i:int = Math.round(n);
			if (i >= 1000)
			{
				var full:int = i / 1000;
				var frac:int = (i % 1000) / 100;
				return frac > 0
				    ? (String(full) + "." + String(frac) + "k")
				    : (String(full) + "k");
			}
			return String(i);
		}

		private function mkLabel(text:String, size:int, color:uint, bold:Boolean):TextField
		{
			var fmt:TextFormat = new TextFormat("Arial", size, color, bold);
			var tf:TextField   = new TextField();
			tf.defaultTextFormat = fmt;
			tf.autoSize      = TextFieldAutoSize.LEFT;
			tf.selectable    = false;
			tf.mouseEnabled  = false;
			tf.text          = text;
			return tf;
		}

		private function valid(s:String):Boolean
		{
			return s != null && s.length > 0 && s != "undefined" && s != "null";
		}
	}
}
