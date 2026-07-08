package skua.module
{
	import flash.display.DisplayObject;
	import flash.display.DisplayObjectContainer;

	/**
	 * Speeds up the natural (non-stunned) case of hopping through a same-map
	 * door. The real mechanism (traced in the game's own World class): clicking
	 * into a door's trigger flips world.strFrame immediately, then calls
	 * world.map.gotoAndPlay("Blank") — the map's timeline plays forward from a
	 * "Blank" frame to a frame labeled after the destination cell over a few
	 * real-time frames before the avatar is actually repositioned. That's the
	 * ~100ms gap DebugPanel's REC captures showed.
	 *
	 * This does NOT touch any validation — whatever server-side approval a
	 * transition needs (e.g. PvP's stun/root check in moveToCellByIDa) already
	 * happened before strFrame changes; this only fires after that.
	 *
	 * First attempt forced world.map.gotoAndStop(cell) alone — confirmed (via
	 * DebugPanel log) that it correctly landed on the destination frame/label,
	 * but the avatar still took the same ~100ms to reposition, proving the
	 * reposition isn't driven by timeline position at all. This second attempt
	 * builds on that: NOW that we forced the destination frame to load, its
	 * content (children) should actually be populated in this same synchronous
	 * call — unlike the earlier pad-marker attempt, which searched for a
	 * strPad-named object before the destination frame had loaded at all (and
	 * found nothing). Re-searching immediately after our own gotoAndStop gives
	 * that theory a fair second try with corrected timing. If found, forces the
	 * avatar there directly instead of waiting for the native code to do it.
	 */
	public class FastDoorEnter extends Module
	{
		private var _lastCell:String = "";

		public function FastDoorEnter() { super("FastDoorEnter"); }

		override public function onToggle(game:*):void
		{
			_lastCell = "";
			if (enabled)
			{
				try { _lastCell = game.world.strFrame; } catch (e:Error) {}
			}
		}

		override public function onFrame(game:*):void
		{
			try
			{
				var cell:String = game.world.strFrame;
				if (cell == _lastCell) return;
				_lastCell = cell;

				game.world.map.gotoAndStop(cell);

				var padName:String = game.world.strPad;
				var root:DisplayObjectContainer = game.world.map as DisplayObjectContainer;
				var pad:DisplayObject = padName ? findPad(root, padName, 0) : null;

				if (pad == null)
				{
					DebugPanel.append("[FastDoorEnter] cell->" + cell + " landed frame=" + game.world.map.currentFrame +
						" label=" + game.world.map.currentLabel + " pad=\"" + padName + "\" still NOT FOUND post-jump");
					return;
				}

				var pMC:DisplayObject = game.world.myAvatar.pMC as DisplayObject;
				if (pMC == null) return;

				var padParent:DisplayObjectContainer = pad.parent;
				if (padParent && pMC.parent !== padParent)
					padParent.addChild(pMC);

				pMC.x = pad.x;
				pMC.y = pad.y;
				DebugPanel.append("[FastDoorEnter] cell->" + cell + " pad=\"" + padName + "\" FOUND post-jump at (" +
					int(pad.x) + "," + int(pad.y) + ") — forced avatar there early");
			}
			catch (err:Error)
			{
				DebugPanel.append("[FastDoorEnter] cell->" + _lastCell + " FAILED: " + err.message);
			}
		}

		private function findPad(obj:DisplayObjectContainer, name:String, depth:int):DisplayObject
		{
			if (obj == null || depth > 6) return null;

			var n:int = 0;
			try { n = obj.numChildren; } catch (ne:Error) { return null; }

			for (var i:int = 0; i < n; i++)
			{
				var child:DisplayObject;
				try { child = obj.getChildAt(i); } catch (ce:Error) { continue; }
				if (child == null) continue;

				var nm:String = "";
				try { nm = child.name; } catch (nme:Error) {}
				if (nm == name) return child;

				var cc:DisplayObjectContainer = child as DisplayObjectContainer;
				if (cc)
				{
					var found:DisplayObject = findPad(cc, name, depth + 1);
					if (found) return found;
				}
			}
			return null;
		}
	}
}
