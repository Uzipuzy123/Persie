package skua.module
{
	import flash.display.DisplayObject;
	import flash.display.GradientType;
	import flash.display.Sprite;
	import flash.geom.Matrix;
	import flash.text.TextField;
	import flash.text.TextFieldAutoSize;
	import flash.text.TextFormat;

	public class PlayerHPBars extends Module
	{
		private static const TAG:String = "skua_hpbar";
		private static const BAR_W:int  = 118;
		private static const HP_H:int   = 10;
		private static const MP_H:int   = 5;
		private static const GAP:int    = 2;

		private var _scale:Number = 0.6;
		private var _styleId:int  = 0; // 0-12

		public function PlayerHPBars() { super("PlayerHPBars"); }

		public function setScale(value:int):void
		{
			_scale = value < 10 ? 0.1 : (value > 100 ? 1.0 : value / 100.0);
		}

		public function setStyle(id:int):void { _styleId = id; }

		override public function onToggle(game:*):void
		{
			if (!enabled) removeAll(game);
			else          apply(game);
		}

		override public function onFrame(game:*):void { apply(game); }

		// ── main loop ────────────────────────────────────────────────────────

		private function apply(game:*):void
		{
			var myTeam:* = null;
			try { myTeam = game.world.myAvatar.objData.strTeam; } catch (e:Error) {}

			for (var aid:* in game.world.avatars)
			{
				var av:* = game.world.avatars[aid];
				try
				{
					if (!av || !av.pMC || !av.dataLeaf) continue;

					var bar:Sprite = av.pMC.getChildByName(TAG) as Sprite;
					if (bar == null)
					{
						bar               = new Sprite();
						bar.name          = TAG;
						bar.mouseEnabled  = false;
						bar.mouseChildren = false;
						av.pMC.addChild(bar);
					}

					var hp:int    = int(av.dataLeaf.intHP);
					var maxHP:int = int(av.dataLeaf.intHPMax);
					if (maxHP == 0) maxHP = int(av.dataLeaf.intMaxHP);
					if (maxHP == 0) maxHP = int(av.dataLeaf.nMaxHP);
					if (maxHP <= 0) maxHP = 1;

					var mp:int    = int(av.dataLeaf.intMP);
					var maxMP:int = int(av.dataLeaf.intMPMax);
					if (maxMP == 0) maxMP = int(av.dataLeaf.intMaxMP);
					if (maxMP == 0) maxMP = int(av.dataLeaf.nMaxMP);
					if (maxMP < 0)  maxMP = 0;

					var isEnemy:Boolean = resolveEnemy(av, myTeam);
					var bw:int = Math.max(20, Math.round(BAR_W * _scale));
					var hh:int = Math.max(3,  Math.round(HP_H  * _scale));
					var mh:int = Math.max(2,  Math.round(MP_H  * _scale));

					var totalH:int;
					switch (_styleId)
					{
						case 1:  totalH = drawWoW(bar, hp, maxHP, isEnemy, bw, hh);                    break;
						case 2:  totalH = drawFortnite(bar, hp, maxHP, mp, maxMP, isEnemy, bw, hh, mh);break;
						case 3:  totalH = drawValorant(bar, hp, maxHP, isEnemy, bw);                   break;
						case 4:  totalH = drawRune(bar, hp, maxHP, bw, mh);                            break;
						case 5:  totalH = drawOverwatch(bar, hp, maxHP, mp, maxMP, isEnemy, bw, hh);   break;
						case 6:  totalH = drawEldenRing(bar, hp, maxHP, mp, maxMP, bw, hh, mh);        break;
						case 7:  totalH = drawGTA(bar, hp, maxHP, mp, maxMP, isEnemy, bw, hh, mh);     break;
						case 8:  totalH = drawMinecraft(bar, hp, maxHP, bw);                           break;
						case 9:  totalH = drawNeonGlow(bar, hp, maxHP, isEnemy, bw);                   break;
						case 10: totalH = drawGradient(bar, hp, maxHP, isEnemy, bw, hh);               break;
						case 11: totalH = drawPixelBlocks(bar, hp, maxHP, isEnemy, bw, hh);            break;
						case 12: totalH = drawAQWGold(bar, hp, maxHP, mp, maxMP, bw, hh, mh);          break;
						default: totalH = drawLoL(bar, hp, maxHP, mp, maxMP, isEnemy, bw, hh, mh);     break;
					}

					// Always hide the player name — already shown by AQW natively
					tf(bar, "_name", 8, 0xFFFFFF, false).visible = false;

					bar.x = -(bw * 0.5);
					try   { bar.y = av.pMC.pname.y - totalH - 4; }
					catch (e2:Error) { bar.y = -120; }
				}
				catch (e:Error) {}
			}
		}

		// ── League of Legends ────────────────────────────────────────────────

		private function drawLoL(bar:Sprite, hp:int, maxHP:int,
		                          mp:int, maxMP:int, isEnemy:Boolean,
		                          bw:int, hh:int, mh:int):int
		{
			var hpCol:uint = isEnemy ? 0xC72020 : 0x57C030;
			var inner:int  = Math.max(1, bw - 2);
			var hpFW:int   = Math.round(inner * sat(hp / maxHP));
			var mpFW:int   = maxMP > 0 ? Math.round(inner * sat(mp / maxMP)) : 0;
			var mpY:int    = hh + GAP;
			var g:*        = bar.graphics;
			g.clear();

			px(g, 0x000000, 0, 0, bw, hh);
			px(g, 0x0A0A0A, 1, 1, inner, hh - 2);
			if (hpFW > 0) px(g, hpCol, 1, 1, hpFW, hh - 2);

			var segs:int = Math.floor(maxHP / 200);
			if (segs > 1)
			{
				g.lineStyle(1, 0x000000, 0.55);
				for (var i:int = 1; i < segs; i++)
				{
					var sx:int = 1 + Math.round(inner * (i * 200.0 / maxHP));
					if (sx >= bw - 1) continue;
					g.moveTo(sx, 1); g.lineTo(sx, hh - 2);
				}
				g.lineStyle();
			}

			px(g, 0x000000, 0, mpY, bw, mh);
			px(g, 0x0A0A0A, 1, mpY + 1, inner, mh - 2);
			if (mpFW > 0) px(g, 0x1E8FD8, 1, mpY + 1, mpFW, mh - 2);

			var fs:int = Math.max(7, Math.round(10 * _scale));
			showHP(bar, fs, 0xCCCCCC, hp, maxHP, bw, 0);
			showMP(bar, fs, mp, maxMP, bw, mpY);
			return hh + GAP + mh;
		}

		// ── World of Warcraft ────────────────────────────────────────────────

		private function drawWoW(bar:Sprite, hp:int, maxHP:int,
		                          isEnemy:Boolean, bw:int, hh:int):int
		{
			var ratio:Number = sat(hp / maxHP);
			var fillCol:uint;
			if (!isEnemy) fillCol = ratio > 0.5 ? 0x49B54A : (ratio > 0.25 ? 0xF7A933 : 0xC8391A);
			else          fillCol = ratio > 0.5 ? 0xC72020 : 0x8B0000;

			var inner:int = Math.max(1, bw - 2);
			var fillW:int = Math.round(inner * ratio);
			var panH:int  = hh + 4;
			var g:*       = bar.graphics;
			g.clear();

			px(g, 0x111111, -2, 0, bw + 4, panH);
			px(g, 0x222222, 0, 2, bw, hh);
			if (fillW > 0)
			{
				px(g, fillCol, 0, 2, fillW, hh);
				px(g, 0xFFFFFF, 0, 2, fillW, Math.max(1, Math.round(hh * 0.35)), 0.12);
			}
			g.lineStyle(1, 0x000000, 1); g.drawRect(0, 2, bw, hh); g.lineStyle();

			hideHP(bar); hideMP(bar);
			return panH;
		}

		// ── Fortnite ─────────────────────────────────────────────────────────

		private function drawFortnite(bar:Sprite, hp:int, maxHP:int,
		                               mp:int, maxMP:int, isEnemy:Boolean,
		                               bw:int, hh:int, mh:int):int
		{
			var hpFW:int   = Math.round(bw * sat(hp / maxHP));
			var mpFW:int   = maxMP > 0 ? Math.round(bw * sat(mp / maxMP)) : 0;
			var hpY:int    = mh + GAP;
			var hpCol:uint = isEnemy ? 0xFF3333 : 0xE8C020;
			var g:*        = bar.graphics;
			g.clear();

			px(g, 0x0A1530, 0, 0, bw, mh);
			if (mpFW > 0) px(g, 0x5599FF, 0, 0, mpFW, mh);
			px(g, 0x1A0800, 0, hpY, bw, hh);
			if (hpFW > 0) px(g, hpCol, 0, hpY, hpFW, hh);

			hideHP(bar); hideMP(bar);
			return mh + GAP + hh;
		}

		// ── Valorant ─────────────────────────────────────────────────────────

		private function drawValorant(bar:Sprite, hp:int, maxHP:int,
		                               isEnemy:Boolean, bw:int):int
		{
			var ratio:Number  = sat(hp / maxHP);
			var barH:int      = Math.max(2, Math.round(3 * _scale));
			var fillW:int     = Math.round(bw * ratio);
			var fillCol:uint  = isEnemy ? 0xFF4444 : 0x44FF99;
			var fs:int        = Math.max(7, Math.round(9 * _scale));
			var g:*           = bar.graphics;
			g.clear();

			px(g, 0x2A2A2A, 0, 0, bw, barH);
			if (fillW > 0) px(g, fillCol, 0, 0, fillW, barH);
			g.lineStyle(1, 0x000000, 0.6);
			g.moveTo(Math.round(bw * 0.25), 0); g.lineTo(Math.round(bw * 0.25), barH);
			g.moveTo(Math.round(bw * 0.50), 0); g.lineTo(Math.round(bw * 0.50), barH);
			g.moveTo(Math.round(bw * 0.75), 0); g.lineTo(Math.round(bw * 0.75), barH);
			g.lineStyle();

			var ht:TextField = tf(bar, "_hp", fs, fillCol, true);
			ht.defaultTextFormat = new TextFormat("Arial", fs, fillCol, true);
			ht.text = String(hp); ht.x = bw + 4; ht.y = -1; ht.visible = true;
			hideMP(bar);
			return barH;
		}

		// ── Runescape ────────────────────────────────────────────────────────

		private function drawRune(bar:Sprite, hp:int, maxHP:int, bw:int, mh:int):int
		{
			var fillW:int = Math.round(bw * sat(hp / maxHP));
			var barH:int  = Math.max(2, mh);
			var g:*       = bar.graphics;
			g.clear();
			px(g, 0x000000, 0, 0, bw, barH);
			if (fillW > 0) px(g, 0x00FF00, 0, 0, fillW, barH);
			hideHP(bar); hideMP(bar);
			return barH;
		}

		// ── Overwatch ────────────────────────────────────────────────────────

		private function drawOverwatch(bar:Sprite, hp:int, maxHP:int,
		                                mp:int, maxMP:int, isEnemy:Boolean,
		                                bw:int, hh:int):int
		{
			var ratio:Number     = sat(hp / maxHP);
			var armorRatio:Number = maxMP > 0 ? sat(mp / maxMP) : 0;
			var inner:int        = Math.max(1, bw - 2);
			var fillW:int        = Math.round(inner * ratio);
			var armorW:int       = Math.round(inner * armorRatio);
			var fillCol:uint     = isEnemy ? 0xDD4444 : 0xDDDDFF;
			var armorH:int       = Math.max(2, Math.round(hh * 0.3));
			var g:*              = bar.graphics;
			g.clear();

			px(g, 0x0C1E35, 0, 0, bw, hh);
			if (fillW > 0) px(g, fillCol, 1, 1, fillW, hh - 2);
			if (armorW > 0) px(g, 0xF5C518, 1, hh - armorH - 1, armorW, armorH);

			var segs:int = Math.floor(maxHP / 25);
			if (segs > 1)
			{
				g.lineStyle(1, 0x000000, 0.45);
				for (var i:int = 1; i < segs; i++)
				{
					var sx:int = 1 + Math.round(inner * (i * 25.0 / maxHP));
					if (sx >= bw - 1) continue;
					g.moveTo(sx, 1); g.lineTo(sx, hh - 2);
				}
				g.lineStyle();
			}
			g.lineStyle(1, 0x334455, 1); g.drawRect(0, 0, bw, hh); g.lineStyle();

			var fs:int = Math.max(7, Math.round(9 * _scale));
			showHP(bar, fs, 0xCCCCCC, hp, maxHP, bw, 0);
			hideMP(bar);
			return hh;
		}

		// ── Elden Ring ───────────────────────────────────────────────────────

		private function drawEldenRing(bar:Sprite, hp:int, maxHP:int,
		                                mp:int, maxMP:int,
		                                bw:int, hh:int, mh:int):int
		{
			var hpFW:int   = Math.round((bw - 2) * sat(hp / maxHP));
			var mpFW:int   = maxMP > 0 ? Math.round((bw - 2) * sat(mp / maxMP)) : 0;
			var mpY:int    = hh + GAP;
			var stamH:int  = Math.max(2, Math.round(2 * _scale));
			var stamY:int  = mpY + mh + GAP;
			var stamFW:int = Math.round((bw - 2) * sat(hp / maxHP));
			var g:*        = bar.graphics;
			g.clear();

			// HP — blood red
			px(g, 0x0A0000, 0, 0, bw, hh);
			px(g, 0x3A0000, 1, 1, bw - 2, hh - 2);
			if (hpFW > 0)
			{
				px(g, 0x882222, 1, 1, hpFW, hh - 2);
				px(g, 0xCC3333, 1, 1, hpFW, Math.max(1, Math.round((hh - 2) * 0.4)));
			}
			g.lineStyle(1, 0x5A1A00, 1); g.drawRect(0, 0, bw, hh); g.lineStyle();

			// FP — dark blue
			px(g, 0x000A14, 0, mpY, bw, mh);
			px(g, 0x001A2A, 1, mpY + 1, bw - 2, mh - 2);
			if (mpFW > 0) px(g, 0x2255AA, 1, mpY + 1, mpFW, mh - 2);
			g.lineStyle(1, 0x003355, 1); g.drawRect(0, mpY, bw, mh); g.lineStyle();

			// Stamina strip — bright green
			px(g, 0x001100, 0, stamY, bw, stamH);
			if (stamFW > 0) px(g, 0x00CC44, 1, stamY, stamFW, stamH);

			var fs:int = Math.max(7, Math.round(9 * _scale));
			showHP(bar, fs, 0xAA7766, hp, maxHP, bw, 0);
			hideMP(bar);
			return stamY + stamH;
		}

		// ── GTA V ────────────────────────────────────────────────────────────

		private function drawGTA(bar:Sprite, hp:int, maxHP:int,
		                          mp:int, maxMP:int, isEnemy:Boolean,
		                          bw:int, hh:int, mh:int):int
		{
			var hpFW:int   = Math.round(bw * sat(hp / maxHP));
			var arFW:int   = maxMP > 0 ? Math.round(bw * sat(mp / maxMP)) : 0;
			var arY:int    = hh + GAP;
			var hpCol:uint = isEnemy ? 0xFF3333 : 0x33CC00;
			var g:*        = bar.graphics;
			g.clear();

			// Health
			px(g, 0x001100, 0, 0, bw, hh);
			if (hpFW > 0)
			{
				px(g, hpCol, 0, 0, hpFW, hh);
				px(g, 0xFFFFFF, 0, 0, hpFW, Math.max(1, Math.round(hh * 0.25)), 0.18);
			}
			// Armor / mana
			px(g, 0x001A1A, 0, arY, bw, mh);
			if (arFW > 0)
			{
				px(g, 0x00BBCC, 0, arY, arFW, mh);
				px(g, 0xFFFFFF, 0, arY, arFW, Math.max(1, Math.round(mh * 0.35)), 0.15);
			}

			hideHP(bar); hideMP(bar);
			return hh + GAP + mh;
		}

		// ── Minecraft ────────────────────────────────────────────────────────

		private function drawMinecraft(bar:Sprite, hp:int, maxHP:int, bw:int):int
		{
			var p:int    = Math.max(1, Math.round(_scale * 1.5));
			var hw:int   = 5 * p;
			var hh2:int  = 5 * p;
			var hgap:int = Math.max(1, p);
			var nH:int   = Math.min(10, Math.floor(bw / (hw + hgap)));
			if (nH < 1) nH = 1;

			var filled:int = Math.round(sat(hp / maxHP) * nH);
			var g:*        = bar.graphics;
			g.clear();

			for (var i:int = 0; i < nH; i++)
			{
				var hx:int   = i * (hw + hgap);
				var full:Boolean = i < filled;
				var col:uint = full ? 0xCC0000 : 0x220000;
				var hi:uint  = full ? 0xFF6666 : 0x330000;
				// 5×5 pixel heart
				px(g, col, hx + p,   0,     p,  p);   // left bump
				px(g, col, hx + 3*p, 0,     p,  p);   // right bump
				px(g, hi,  hx,       p,     hw, p);   // row 1 (highlight)
				px(g, col, hx,       2*p,   hw, p);   // row 2
				px(g, col, hx + p,   3*p,   3*p, p);  // row 3
				px(g, col, hx + 2*p, 4*p,   p,  p);   // tip
			}

			hideHP(bar); hideMP(bar);
			return hh2;
		}

		// ── Neon Glow ────────────────────────────────────────────────────────

		private function drawNeonGlow(bar:Sprite, hp:int, maxHP:int,
		                               isEnemy:Boolean, bw:int):int
		{
			var ratio:Number = sat(hp / maxHP);
			var barH:int     = Math.max(3, Math.round(4 * _scale));
			var fillW:int    = Math.round(bw * ratio);
			var col:uint     = isEnemy ? 0xFF0077 : 0x00FFEE;
			var g:*          = bar.graphics;
			g.clear();

			if (fillW > 0)
			{
				px(g, col, -3, -3, fillW + 6, barH + 6, 0.04);
				px(g, col, -2, -2, fillW + 4, barH + 4, 0.07);
				px(g, col, -1, -1, fillW + 2, barH + 2, 0.12);
			}
			px(g, 0x050505, 0, 0, bw, barH);
			if (fillW > 0)
			{
				px(g, col, 0, 0, fillW, barH, 0.45);
				px(g, col, 0, Math.round(barH * 0.25), fillW, Math.round(barH * 0.5));
			}

			hideHP(bar); hideMP(bar);
			return barH + 3;
		}

		// ── Gradient ─────────────────────────────────────────────────────────

		private function drawGradient(bar:Sprite, hp:int, maxHP:int,
		                               isEnemy:Boolean, bw:int, hh:int):int
		{
			var ratio:Number = sat(hp / maxHP);
			var fillW:int    = Math.round(bw * ratio);
			var g:*          = bar.graphics;
			g.clear();

			var r:int, gv:int;
			if (ratio >= 0.5) { r = Math.round(255 * (1.0 - ratio) * 2); gv = 255; }
			else               { r = 255; gv = Math.round(255 * ratio * 2); }
			var fillCol:uint  = (r << 16) | (gv << 8);
			var brightCol:uint = ((Math.min(255, r  + 60) & 0xFF) << 16)
			                   | ((Math.min(255, gv + 60) & 0xFF) << 8);
			if (isEnemy) { fillCol = 0xFF2222; brightCol = 0xFF6644; }

			px(g, 0x0A0A0A, 0, 0, bw, hh);

			if (fillW > 0)
			{
				var m:Matrix = new Matrix();
				m.createGradientBox(fillW, hh, 0, 0, 0);
				g.beginGradientFill(GradientType.LINEAR,
					[brightCol, fillCol], [1, 1], [0, 255], m);
				g.drawRect(0, 0, fillW, hh);
				g.endFill();
				px(g, 0xFFFFFF, 0, 0, fillW, Math.max(1, Math.round(hh * 0.3)), 0.15);
			}
			g.lineStyle(1, 0x1A1A1A, 1); g.drawRect(0, 0, bw, hh); g.lineStyle();

			var fs:int = Math.max(7, Math.round(9 * _scale));
			showHP(bar, fs, 0xCCCCCC, hp, maxHP, bw, 0);
			hideMP(bar);
			return hh;
		}

		// ── Pixel Blocks ─────────────────────────────────────────────────────

		private function drawPixelBlocks(bar:Sprite, hp:int, maxHP:int,
		                                  isEnemy:Boolean, bw:int, hh:int):int
		{
			var gap:int     = Math.max(1, Math.round(_scale));
			var nBlocks:int = 20;
			var bkW:int     = Math.floor((bw - gap * (nBlocks - 1)) / nBlocks);
			if (bkW < 2)  { bkW = 2; nBlocks = Math.floor(bw / (bkW + gap)); }

			var filled:int = Math.round(sat(hp / maxHP) * nBlocks);
			var onCol:uint = isEnemy ? 0xCC2222 : 0x22CC55;
			var g:*        = bar.graphics;
			g.clear();

			for (var i:int = 0; i < nBlocks; i++)
			{
				var bx:int   = i * (bkW + gap);
				var col:uint = i < filled ? onCol : 0x111111;
				px(g, col, bx, 0, bkW, hh);
				if (i < filled)
					px(g, 0xFFFFFF, bx, 0, bkW, Math.max(1, Math.round(hh * 0.3)), 0.12);
			}

			hideHP(bar); hideMP(bar);
			return hh;
		}

		// ── AQW Gold ─────────────────────────────────────────────────────────

		private function drawAQWGold(bar:Sprite, hp:int, maxHP:int,
		                              mp:int, maxMP:int,
		                              bw:int, hh:int, mh:int):int
		{
			var hpFW:int = Math.round((bw - 2) * sat(hp / maxHP));
			var mpFW:int = maxMP > 0 ? Math.round((bw - 2) * sat(mp / maxMP)) : 0;
			var mpY:int  = hh + GAP;
			var g:*      = bar.graphics;
			g.clear();

			px(g, 0x0E0900, 0, 0, bw, hh);
			px(g, 0x1A1000, 1, 1, bw - 2, hh - 2);
			if (hpFW > 0)
			{
				px(g, 0x9A6A10, 1, 1, hpFW, hh - 2);
				px(g, 0xC8A040, 1, 1, hpFW, Math.max(1, Math.round((hh - 2) * 0.45)));
			}
			g.lineStyle(1, 0xC8A040, 0.8); g.drawRect(0, 0, bw, hh); g.lineStyle();

			px(g, 0x00050F, 0, mpY, bw, mh);
			px(g, 0x000A1A, 1, mpY + 1, bw - 2, mh - 2);
			if (mpFW > 0) px(g, 0x3366CC, 1, mpY + 1, mpFW, mh - 2);
			g.lineStyle(1, 0x224488, 0.8); g.drawRect(0, mpY, bw, mh); g.lineStyle();

			var fs:int = Math.max(7, Math.round(9 * _scale));
			showHP(bar, fs, 0xC8A040, hp, maxHP, bw, 0);
			var mt:TextField = tf(bar, "_mp", Math.max(6, fs - 1), 0x5588CC, false);
			mt.visible = maxMP > 0;
			if (maxMP > 0)
			{
				mt.defaultTextFormat = new TextFormat("Arial", Math.max(6, fs - 1), 0x5588CC, false);
				mt.text = mp + " / " + maxMP; mt.x = bw + 5; mt.y = mpY;
			}
			return hh + GAP + mh;
		}

		// ── helpers ──────────────────────────────────────────────────────────

		private function sat(v:Number):Number { return v < 0 ? 0 : (v > 1 ? 1 : v); }

		private function px(g:*, col:uint, x:Number, y:Number, w:Number, h:Number, a:Number = 1):void
		{
			g.beginFill(col, a); g.drawRect(x, y, w, h); g.endFill();
		}

		private function tf(bar:Sprite, nm:String, sz:int, col:uint, bold:Boolean):TextField
		{
			var t:TextField = bar.getChildByName(nm) as TextField;
			if (t == null)
			{
				t = new TextField();
				t.name = nm;
				t.defaultTextFormat = new TextFormat("Arial", sz, col, bold);
				t.autoSize   = TextFieldAutoSize.LEFT;
				t.selectable = false;
				t.mouseEnabled = false;
				bar.addChild(t);
			}
			return t;
		}

		private function showHP(bar:Sprite, fs:int, col:uint, hp:int, maxHP:int, bw:int, y:int):void
		{
			var t:TextField = tf(bar, "_hp", fs, col, false);
			t.defaultTextFormat = new TextFormat("Arial", fs, col, false);
			t.text = hp + " / " + maxHP; t.x = bw + 5; t.y = y; t.visible = true;
		}

		private function showMP(bar:Sprite, fs:int, mp:int, maxMP:int, bw:int, y:int):void
		{
			var t:TextField = tf(bar, "_mp", Math.max(6, fs - 2), 0x88CCFF, false);
			t.visible = maxMP > 0;
			if (maxMP > 0)
			{
				t.defaultTextFormat = new TextFormat("Arial", Math.max(6, fs - 2), 0x88CCFF, false);
				t.text = mp + " / " + maxMP; t.x = bw + 5; t.y = y;
			}
		}

		private function hideHP(bar:Sprite):void { tf(bar, "_hp", 7, 0xCCCCCC, false).visible = false; }
		private function hideMP(bar:Sprite):void { tf(bar, "_mp", 6, 0x88CCFF, false).visible = false; }

		private function resolveEnemy(av:*, myTeam:*):Boolean
		{
			if (av.isMyAvatar) return false;
			try
			{
				var t:* = av.objData.strTeam;
				if (myTeam != null && t != null) return (myTeam != t);
			}
			catch (e:Error) {}
			return true;
		}

		private function removeAll(game:*):void
		{
			try
			{
				for (var aid:* in game.world.avatars)
				{
					var av:* = game.world.avatars[aid];
					try
					{
						if (!av || !av.pMC) continue;
						var b:DisplayObject = av.pMC.getChildByName(TAG);
						if (b) av.pMC.removeChild(b);
					}
					catch (e:Error) {}
				}
			}
			catch (e:Error) {}
		}
	}
}
