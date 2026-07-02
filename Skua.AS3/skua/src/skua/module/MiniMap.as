package skua.module
{
	import flash.display.GradientType;
	import flash.display.Graphics;
	import flash.display.Shape;
	import flash.display.Sprite;
	import flash.display.Stage;
	import flash.events.MouseEvent;
	import flash.geom.Matrix;
	import flash.text.TextField;
	import flash.text.TextFieldAutoSize;
	import flash.text.TextFormat;

	public class MiniMap extends Module
	{
		private static const CW:int     = 22;
		private static const CH:int     = 18;
		private static const GAP:int    = 2;
		private static const PAD:int    = 6;
		private static const HEADER:int = 14;
		private static const FOOTER:int = 12;
		private static const COLS:int   = 9;
		private static const ROWS:int   = 2;
		private static const MARGIN:int = 10;
		private static const MIN_RX:Number = 200;
		private static const MIN_RY:Number = 150;
		private static const GOLD:uint  = 0xC89B3C;
		private static const GOLD2:uint = 0x785A28;

		private static const CELLS:Array = [
			{ label:"SZ",  col:0, row:1, fill:0x041204, border:0x1C7A1C, tc:0x2ECC71,
			  names:["entero0","enter0"] },
			{ label:"B3",  col:1, row:1, fill:0x060f1e, border:0x2A5F9E, tc:0x7EB4EA,
			  names:["morale0c"] },
			{ label:"B2",  col:2, row:1, fill:0x060f1e, border:0x2A5F9E, tc:0x7EB4EA,
			  names:["morale0b"] },
			{ label:"B1",  col:3, row:1, fill:0x060f1e, border:0x2A5F9E, tc:0x7EB4EA,
			  names:["morale0a"] },
			{ label:"MID", col:4, row:1, fill:0x1a1400, border:GOLD,     tc:GOLD,
			  names:["crosslower"] },
			{ label:"B1",  col:5, row:1, fill:0x060f1e, border:0x2A5F9E, tc:0x7EB4EA,
			  names:["morale1a"] },
			{ label:"B2",  col:6, row:1, fill:0x060f1e, border:0x2A5F9E, tc:0x7EB4EA,
			  names:["morale1b"] },
			{ label:"B3",  col:7, row:1, fill:0x060f1e, border:0x2A5F9E, tc:0x7EB4EA,
			  names:["morale1c"] },
			{ label:"SZ",  col:8, row:1, fill:0x120404, border:0x8C2020, tc:0xE74C3C,
			  names:["enter1"] },
			{ label:"Cap", col:1, row:0, fill:0x0e0814, border:0x7B3FA0, tc:0xBB77EE,
			  names:["captain0","capture0","cap0","capturea","capa","flag0","cap_a"] },
			{ label:"R2",  col:2, row:0, fill:0x060f1e, border:0x2A5F9E, tc:0x7EB4EA,
			  names:["resource0b"] },
			{ label:"R1",  col:3, row:0, fill:0x060f1e, border:0x2A5F9E, tc:0x7EB4EA,
			  names:["resource0a"] },
			{ label:"UP",  col:4, row:0, fill:0x1a1400, border:GOLD,     tc:GOLD,
			  names:["crossupper"] },
			{ label:"R1",  col:5, row:0, fill:0x060f1e, border:0x2A5F9E, tc:0x7EB4EA,
			  names:["resource1a"] },
			{ label:"R2",  col:6, row:0, fill:0x060f1e, border:0x2A5F9E, tc:0x7EB4EA,
			  names:["resource1b"] },
			{ label:"Cap", col:7, row:0, fill:0x0e0814, border:0x7B3FA0, tc:0xBB77EE,
			  names:["captain1","capture1","cap1","captureb","capb","flag1","cap_b"] },
		];

		private static const MID_IDX:int = 4;
		private static const SZ_A:int    = 0;   // enter0 cell index (green SZ)
		private static const SZ_B:int    = 8;   // enter1 cell index (red SZ)

		// Persists across enable/disable so position and scale are remembered
		private static var _savedX:Number     = -1e9;
		private static var _savedY:Number     = -1e9;
		private static var _savedScale:Number = 1.0;

		private var _overlay:Sprite;
		private var _staticLayer:Shape;
		private var _dynamicLayer:Shape;
		private var _roomLabel:TextField;
		private var _dragHandle:Sprite;
		private var _btnMinus:Sprite;
		private var _btnPlus:Sprite;
		private var _scale:Number;
		private var _stage:Stage;
		private var _cellBounds:Array;
		private var _playerCells:Object;
		private var _myPrevCellIdx:int      = -2;
		private var _mySZ:int               = -1;   // SZ_A or SZ_B, set on first SZ entry per match
		private var _lastDebugDump:String   = "";

		public function MiniMap() { super("MiniMap"); }

		private function oW():int { return PAD*2 + COLS*(CW+GAP) - GAP; }
		private function oH():int { return PAD + HEADER + 4 + ROWS*(CH+GAP) - GAP + 4 + FOOTER + PAD; }
		private function cX(col:int):Number { return PAD + col*(CW+GAP); }
		private function cY(row:int):Number { return PAD + HEADER + 4 + row*(CH+GAP); }
		private function footerY():Number   { return cY(1) + CH + 4; }

		override public function onToggle(game:*):void
		{
			if (enabled)
			{
				_scale        = _savedScale;
				_overlay      = new Sprite();
				_staticLayer  = new Shape();
				_dynamicLayer = new Shape();
				_overlay.addChild(_staticLayer);
				_overlay.addChild(_dynamicLayer);

				// Overlay itself is not a hit target; individual children opt in.
				// Shape has no mouseEnabled — it never receives mouse events by design.
				_overlay.mouseEnabled  = false;
				_overlay.mouseChildren = true;

				_cellBounds = [];
				for (var bi:int = 0; bi < CELLS.length; bi++)
					_cellBounds[bi] = { minX:1e9, maxX:-1e9, minY:1e9, maxY:-1e9 };
				_playerCells    = {};
				_myPrevCellIdx  = -2;
				_mySZ           = -1;
				_lastDebugDump  = "";

				drawStatic();
				addControls(game);

				var rfmt:TextFormat = new TextFormat("Arial", 9, GOLD, true);
				_roomLabel                    = new TextField();
				_roomLabel.defaultTextFormat  = rfmt;
				_roomLabel.autoSize           = TextFieldAutoSize.LEFT;
				_roomLabel.selectable         = false;
				_roomLabel.mouseEnabled       = false;
				_roomLabel.text               = "—";
				_overlay.addChild(_roomLabel);

				_overlay.scaleX = _scale;
				_overlay.scaleY = _scale;

				try
				{
					_stage = game.stage as Stage;
					if (_savedX > -1e8)
					{
						_overlay.x = _savedX;
						_overlay.y = _savedY;
					}
					else
					{
						_overlay.x = int((_stage.stageWidth - oW() * _scale) * 0.5);
						_overlay.y = MARGIN;
					}
					_stage.addChild(_overlay);
				}
				catch (e:Error)
				{
					_overlay.x = 230;
					_overlay.y = MARGIN;
					try { game.parent.addChild(_overlay); } catch (e2:Error) {}
				}

				apply(game);
			}
			else
			{
				_savedX = _overlay ? _overlay.x : _savedX;
				_savedY = _overlay ? _overlay.y : _savedY;

				try
				{
					if (_dragHandle) _dragHandle.removeEventListener(MouseEvent.MOUSE_DOWN, onDragStart);
					if (_btnPlus)    _btnPlus.removeEventListener(MouseEvent.CLICK, onZoomIn);
					if (_btnMinus)   _btnMinus.removeEventListener(MouseEvent.CLICK, onZoomOut);
					if (_stage)      _stage.removeEventListener(MouseEvent.MOUSE_UP, onDragStop);
				}
				catch (e:Error) {}

				try { if (_overlay && _overlay.parent) _overlay.parent.removeChild(_overlay); }
				catch (e:Error) {}

				_overlay       = null;
				_staticLayer   = null;
				_dynamicLayer  = null;
				_roomLabel     = null;
				_dragHandle    = null;
				_btnPlus       = null;
				_btnMinus      = null;
				_cellBounds    = null;
				_playerCells   = null;
				_myPrevCellIdx = -2;
				_mySZ          = -1;
				_lastDebugDump = "";
				_stage         = null;
			}
		}

		override public function onFrame(game:*):void { apply(game); }

		// ── drag / zoom controls ─────────────────────────────────────────────
		private function addControls(game:*):void
		{
			var totalW:int = oW();
			var btnW:int   = 16;
			var btnH:int   = 12;
			var btnY:int   = int((HEADER - btnH) * 0.5) + 1;

			_btnPlus = makeBtn("+", totalW - PAD - btnW,          btnY, btnW, btnH);
			_btnPlus.addEventListener(MouseEvent.CLICK, onZoomIn);
			_overlay.addChild(_btnPlus);

			_btnMinus = makeBtn("−", totalW - PAD - 2*btnW - 3, btnY, btnW, btnH);
			_btnMinus.addEventListener(MouseEvent.CLICK, onZoomOut);
			_overlay.addChild(_btnMinus);

			// Drag handle: transparent fill over the header (left of buttons)
			var handleW:int = totalW - PAD - 2*btnW - 6;
			_dragHandle = new Sprite();
			_dragHandle.graphics.beginFill(0, 0.01);
			_dragHandle.graphics.drawRect(0, 0, handleW, HEADER + 2);
			_dragHandle.graphics.endFill();
			_dragHandle.useHandCursor = true;
			_dragHandle.buttonMode    = true;
			_overlay.addChild(_dragHandle);
			_dragHandle.addEventListener(MouseEvent.MOUSE_DOWN, onDragStart);

			try
			{
				_stage = game.stage as Stage;
				_stage.addEventListener(MouseEvent.MOUSE_UP, onDragStop);
			}
			catch (e:Error) {}
		}

		private function makeBtn(label:String, bx:int, by:int, bw:int, bh:int):Sprite
		{
			var sp:Sprite = new Sprite();
			sp.graphics.beginFill(GOLD2, 0.7);
			sp.graphics.drawRoundRect(0, 0, bw, bh, 3, 3);
			sp.graphics.endFill();
			sp.graphics.lineStyle(1, GOLD, 0.8);
			sp.graphics.drawRoundRect(0, 0, bw, bh, 3, 3);

			var fmt:TextFormat = new TextFormat("Arial", 10, GOLD, true);
			var tf:TextField   = new TextField();
			tf.defaultTextFormat = fmt;
			tf.autoSize    = TextFieldAutoSize.LEFT;
			tf.selectable  = false;
			tf.mouseEnabled = false;
			tf.text = label;
			tf.x = int((bw - tf.width)  * 0.5);
			tf.y = int((bh - tf.height) * 0.5);
			sp.addChild(tf);

			sp.x              = bx;
			sp.y              = by;
			sp.useHandCursor  = true;
			sp.buttonMode     = true;
			return sp;
		}

		private function onDragStart(e:MouseEvent):void
		{
			_overlay.startDrag();
			e.stopPropagation();
		}

		private function onDragStop(e:MouseEvent):void
		{
			_overlay.stopDrag();
			if (_overlay)
			{
				_savedX = _overlay.x;
				_savedY = _overlay.y;
			}
		}

		private function onZoomIn(e:MouseEvent):void
		{
			e.stopPropagation();
			_scale = Math.min(2.5, _scale + 0.25);
			_overlay.scaleX = _scale;
			_overlay.scaleY = _scale;
			_savedScale = _scale;
		}

		private function onZoomOut(e:MouseEvent):void
		{
			e.stopPropagation();
			_scale = Math.max(0.5, _scale - 0.25);
			_overlay.scaleX = _scale;
			_overlay.scaleY = _scale;
			_savedScale = _scale;
		}

		// ── static drawing ───────────────────────────────────────────────────
		private function drawStatic():void
		{
			var g:Graphics = _staticLayer.graphics;
			var m:Matrix   = new Matrix();
			g.clear();
			var w:int = oW();
			var h:int = oH();

			// Outer frame: gold gradient border
			m.createGradientBox(w, h, Math.PI * 0.5, 0, 0);
			g.beginGradientFill(GradientType.LINEAR, [0x9A7230, 0x3D2808], [1, 1], [0, 255], m);
			g.drawRoundRect(0, 0, w, h, 6, 6);
			g.endFill();

			// Inner panel: deep navy gradient
			m.createGradientBox(w-4, h-4, Math.PI * 0.5, 2, 2);
			g.beginGradientFill(GradientType.LINEAR, [0x0D1E36, 0x060A14], [0.97, 0.97], [0, 255], m);
			g.drawRoundRect(2, 2, w-4, h-4, 5, 5);
			g.endFill();

			// Inner gold highlight line
			g.lineStyle(1, GOLD, 0.45);
			g.drawRoundRect(2, 2, w-4, h-4, 5, 5);

			// Header: lighter navy gradient strip
			m.createGradientBox(w-6, HEADER+2, Math.PI * 0.5, 3, 3);
			g.beginGradientFill(GradientType.LINEAR, [0x1C3050, 0x0A1628], [0.95, 0.95], [0, 255], m);
			g.drawRect(3, 3, w-6, HEADER+2);
			g.endFill();

			// Header bottom divider
			g.lineStyle(1, GOLD, 0.30);
			g.moveTo(4,   HEADER+4);
			g.lineTo(w-4, HEADER+4);

			var hfmt:TextFormat = new TextFormat("Arial", 9, GOLD, true);
			var htf:TextField   = new TextField();
			htf.defaultTextFormat = hfmt;
			htf.autoSize     = TextFieldAutoSize.LEFT;
			htf.selectable   = false;
			htf.mouseEnabled = false;
			htf.text = "PVP MAP";
			htf.x    = PAD;
			htf.y    = int((HEADER - htf.height) * 0.5) + 1;
			_overlay.addChild(htf);

			g.lineStyle(1, GOLD, 0.22);
			g.moveTo(4,   footerY() - 1);
			g.lineTo(w-4, footerY() - 1);

			g.lineStyle(1, 0x0e2040, 1);
			for (var c:int = 0; c < 8; c++)
				hline(g, c, c+1, 1);
			for (var tc:int = 1; tc < 7; tc++)
				hline(g, tc, tc+1, 0);
			for (var vc:int = 1; vc <= 7; vc++)
				vline(g, vc);

			for (var i:int = 0; i < CELLS.length; i++)
			{
				var cell:Object = CELLS[i];
				var cx:Number   = cX(cell.col);
				var cy:Number   = cY(cell.row);

				g.lineStyle(1, uint(cell.border), 0.9);
				g.beginFill(uint(cell.fill), 1);
				g.drawRoundRect(cx, cy, CW, CH, 3, 3);
				g.endFill();

				var lbl:String     = String(cell.label);
				var fs:int         = lbl.length > 2 ? 6 : 7;
				var fmt:TextFormat = new TextFormat("Arial", fs, uint(cell.tc), true);
				var tf:TextField   = new TextField();
				tf.defaultTextFormat = fmt;
				tf.autoSize     = TextFieldAutoSize.LEFT;
				tf.selectable   = false;
				tf.mouseEnabled = false;
				tf.text = lbl;
				tf.x    = cx + int((CW - tf.width)  * 0.5);
				tf.y    = cy + int((CH - tf.height) * 0.5);
				_overlay.addChild(tf);
			}
		}

		private function hline(g:Graphics, colA:int, colB:int, row:int):void
		{
			g.moveTo(cX(colA) + CW, cY(row) + CH * 0.5);
			g.lineTo(cX(colB),      cY(row) + CH * 0.5);
		}
		private function vline(g:Graphics, col:int):void
		{
			g.moveTo(cX(col) + CW * 0.5, cY(0) + CH);
			g.lineTo(cX(col) + CW * 0.5, cY(1));
		}

		// ── per-frame update ─────────────────────────────────────────────────
		private function apply(game:*):void
		{
			if (_dynamicLayer == null) return;
			var g:Graphics = _dynamicLayer.graphics;
			g.clear();

			var myFrame:String = "";
			try { myFrame = String(game.world.strFrame).toLowerCase(); } catch (e:Error) {}

			var myCellIdx:int = findCell(myFrame);

			// Transition into SZ → wipe stale roster from previous match and record our side
			var inSZ:Boolean    = (myCellIdx == SZ_A || myCellIdx == SZ_B);
			var wasInSZ:Boolean = (_myPrevCellIdx == SZ_A || _myPrevCellIdx == SZ_B);
			if (inSZ && !wasInSZ) { TeammateRoster.clear(); _mySZ = myCellIdx; }
			_myPrevCellIdx = myCellIdx;

			var enemySZ:int = (_mySZ == SZ_A) ? SZ_B : (_mySZ == SZ_B ? SZ_A : -1);

			if (_roomLabel)
			{
				var lbl:String = myCellIdx >= 0 ? String(CELLS[myCellIdx].label) : myFrame;
				_roomLabel.text = lbl.length > 0 ? lbl : "—";
				_roomLabel.x    = int((oW() - _roomLabel.width) * 0.5);
				_roomLabel.y    = footerY() + int((FOOTER - _roomLabel.height) * 0.5);
			}

			if (myCellIdx >= 0)
			{
				var hc:Object = CELLS[myCellIdx];
				g.lineStyle(2, 0xFFFFFF, 0.9);
				g.beginFill(0xFFFFFF, 0.09);
				g.drawRoundRect(cX(hc.col), cY(hc.row), CW, CH, 3, 3);
				g.endFill();
			}

			// DEBUG: dump ALL nearby players → DebugPanel (only updates when data changes, so CLEAR sticks)
			try
			{
				var dbgAll:String = "";
				for (var dbgId:* in game.world.avatars)
				{
					var dbgAv:* = game.world.avatars[dbgId];
					if (!dbgAv || !dbgAv.objData) continue;
					var dbgIsMe:Boolean = false;
					try { dbgIsMe = Boolean(dbgAv.isMyAvatar); } catch (de:Error) {}
					if (dbgIsMe) continue;
					var dbgName:String = "";
					try { dbgName = String(dbgAv.objData.strUsername); } catch (dn:Error) {}
					dbgAll += "=== AVATAR: " + dbgName + " ===\n[objData]\n";
					for (var dbgKey:String in dbgAv.objData)
					{
						var dbgVal:* = dbgAv.objData[dbgKey];
						if (dbgVal != null && typeof(dbgVal) == "object")
						{
							dbgAll += "  " + dbgKey + " = {\n";
							for (var dbgSub:String in dbgVal)
								dbgAll += "    " + dbgSub + " = " + String(dbgVal[dbgSub]) + "\n";
							dbgAll += "  }\n";
						}
						else { dbgAll += "  " + dbgKey + " = " + String(dbgVal) + "\n"; }
					}
					dbgAll += "\n";
				}
				for (var dbgUid:* in game.world.areaUsers)
				{
					var dbgU:* = game.world.areaUsers[dbgUid];
					if (!dbgU) continue;
					var dbgUName:String = "";
					try { dbgUName = String(dbgU.objData ? dbgU.objData.strUsername : dbgU.strUsername); } catch (du:Error) {}
					dbgAll += "=== AREA USER: " + dbgUName + " ===\n";
					var dbgUData:* = dbgU.objData || dbgU;
					for (var dbgUKey:String in dbgUData)
					{
						var dbgUVal:* = dbgUData[dbgUKey];
						if (dbgUVal != null && typeof(dbgUVal) == "object")
						{
							dbgAll += "  " + dbgUKey + " = {\n";
							for (var dbgUSub:String in dbgUVal)
								dbgAll += "    " + dbgUSub + " = " + String(dbgUVal[dbgUSub]) + "\n";
							dbgAll += "  }\n";
						}
						else { dbgAll += "  " + dbgUKey + " = " + String(dbgUVal) + "\n"; }
					}
					dbgAll += "\n";
				}
				if (dbgAll.length == 0) dbgAll = "(no other players found)";
				if (dbgAll != _lastDebugDump)
				{
					_lastDebugDump = dbgAll;
					DebugPanel.log(dbgAll);
				}
			}
			catch (dbgErr:Error) { DebugPanel.log("dbg error: " + dbgErr.message); }

			var drawnNames:Object = {};
			var myCell:int = myCellIdx >= 0 ? myCellIdx : MID_IDX;
			try
			{
				for (var aid:* in game.world.avatars)
				{
					var avatar:* = game.world.avatars[aid];
					if (!avatar || !avatar.pMC) continue;

					var aName:String = "";
					try { aName = String(avatar.objData.strUsername).toLowerCase(); } catch (e2:Error) {}
					if (aName.length > 0) drawnNames[aName] = true;

					var cellIdx:int;
					if (avatar.isMyAvatar)
					{
						cellIdx = myCell;
					}
					else
					{
						var aFrame:String = "";
						try { aFrame = String(avatar.objData.strFrame).toLowerCase(); } catch (ef:Error) {}
						if (!aFrame || aFrame == "undefined" || aFrame == "null")
							try { aFrame = String(avatar.strFrame).toLowerCase(); } catch (ef2:Error) {}

						cellIdx = findCell(aFrame);
						if (cellIdx < 0) continue;
					}

					var cell:Object = CELLS[cellIdx];
					var px:Number   = Number(avatar.pMC.x);
					var py:Number   = Number(avatar.pMC.y);

					var pKey:String         = aName.length > 0 ? aName : String(aid);
					var prevCell:*          = _playerCells[pKey];
					var justEntered:Boolean = (prevCell === undefined || int(prevCell) != cellIdx);
					_playerCells[pKey]      = cellIdx;

					if (!justEntered)
					{
						var cb:Object = _cellBounds[cellIdx];
						if (px < cb.minX) cb.minX = px;
						if (px > cb.maxX) cb.maxX = px;
						if (py < cb.minY) cb.minY = py;
						if (py > cb.maxY) cb.maxY = py;
					}

					var bd:Object   = _cellBounds[cellIdx];
					var rX:Number   = Math.max(bd.maxX - bd.minX, MIN_RX);
					var rY:Number   = Math.max(bd.maxY - bd.minY, MIN_RY);
					var midX:Number = (bd.minX + bd.maxX) * 0.5;
					var midY:Number = (bd.minY + bd.maxY) * 0.5;

					var nx:Number = Math.max(-0.82, Math.min(0.82, (px - midX) / (rX * 0.5)));
					var ny:Number = Math.max(-0.82, Math.min(0.82, (py - midY) / (rY * 0.5)));

					var dotX:Number = cX(cell.col) + CW * 0.5 + nx * (CW * 0.5 - 3);
					var dotY:Number = cY(cell.row) + CH * 0.5 + ny * (CH * 0.5 - 3);

					if (avatar.isMyAvatar)
					{
						g.lineStyle(1.5, GOLD2, 0.6);
						g.beginFill(0xFFFFFF, 1);
						g.drawCircle(dotX, dotY, 4);
						g.endFill();
					}
					else
					{
						// Roster member spotted in enemy SZ → they switched teams, evict them.
						if (enemySZ >= 0 && cellIdx == enemySZ && TeammateRoster.isTeammate(aName))
							TeammateRoster.remove(aName);

						// When I'm in SafeZone, every avatar also present is a confirmed teammate.
						if ((myCellIdx == SZ_A || myCellIdx == SZ_B) && cellIdx == myCellIdx && aName.length > 0)
							TeammateRoster.add(aName);

						if (!TeammateRoster.isTeammate(aName)) continue;

						g.lineStyle(1, GOLD2, 0.5);
						g.beginFill(0xFFFFFF, 0.9);
						g.drawCircle(dotX, dotY, 3);
						g.endFill();
					}
				}
			}
			catch (e:Error) {}

			try
			{
				for (var uid:* in game.world.areaUsers)
				{
					var user:* = game.world.areaUsers[uid];
					if (!user) continue;

					try { if (user.isMyAvatar) continue; } catch (es:Error) {}

					var uName:String = "";
					try { uName = String(user.objData ? user.objData.strUsername : user.strUsername).toLowerCase(); }
					catch (en:Error) {}
					if (uName.length > 0 && drawnNames[uName]) continue;

					var uFrame:String = "";
					try { uFrame = String(user.strFrame).toLowerCase(); } catch (ef:Error) {}
					var uCellIdx:int = findCell(uFrame);
					if (uCellIdx < 0) continue;
					if (uCellIdx == myCell) continue;

					// When I'm in SafeZone, every areaUser in the same cell is a confirmed teammate.
					if ((myCellIdx == SZ_A || myCellIdx == SZ_B) && uCellIdx == myCellIdx && uName.length > 0)
						TeammateRoster.add(uName);

					if (!TeammateRoster.isTeammate(uName)) continue;

					var uc:Object    = CELLS[uCellIdx];
					var udotX:Number = cX(uc.col) + CW * 0.5;
					var udotY:Number = cY(uc.row) + CH * 0.5;

					g.lineStyle(1, GOLD2, 0.5);
					g.beginFill(0xFFFFFF, 0.9);
					g.drawCircle(udotX, udotY, 3);
					g.endFill();
				}
			}
			catch (e:Error) {}
		}

		private function findCell(frame:String):int
		{
			if (!frame || frame.length == 0) return -1;
			for (var i:int = 0; i < CELLS.length; i++)
			{
				var names:Array = CELLS[i].names as Array;
				for (var j:int = 0; j < names.length; j++)
					if (names[j] == frame) return i;
			}
			return -1;
		}
	}
}
