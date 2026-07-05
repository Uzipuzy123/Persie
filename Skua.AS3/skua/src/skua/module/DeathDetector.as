package skua.module
{
	import flash.external.ExternalInterface;

	public class DeathDetector extends Module
	{
		private var _prevHP:Number   = -1;
		private var _wasDead:Boolean = false;
		private var _lastAttacker:String = "";

		public function DeathDetector() { super("DeathDetector"); enabled = true; }

		override public function onToggle(game:*):void
		{
			if (!enabled) { _prevHP = -1; _wasDead = false; _lastAttacker = ""; }
		}

		override public function onFrame(game:*):void
		{
			var hp:Number = 0;
			var avatarPresent:Boolean = true;
			try { hp = Number(game.world.myAvatar.dataLeaf.intHP); }
			catch (e:Error) { avatarPresent = false; }

			// Avatar object gone (logout / server change tears it down) — this is not
			// a death, it's a scene transition. Don't touch _prevHP/_wasDead here so
			// a real death mid-transition still isn't falsely re-armed once the
			// avatar comes back on the next map.
			if (!avatarPresent)
				return;

			// While HP is actively dropping, update who is hitting us
			if (_prevHP > 0 && hp > 0 && hp < _prevHP)
				updateAttacker(game);

			// Transition from alive → dead
			if (!_wasDead && _prevHP > 0 && hp <= 0)
			{
				_wasDead = true;
				try { ExternalInterface.call("skuaOnDeath", _lastAttacker); } catch (e:Error) {}
				_lastAttacker = "";
			}

			if (hp > 0) _wasDead = false;
			_prevHP = hp;
		}

		// Walk the cell looking for the most likely attacker each frame HP drops.
		private function updateAttacker(game:*):void
		{
			var myFrame:String = "";
			try { myFrame = String(game.world.myAvatar.objData.strFrame).toLowerCase(); } catch (e:Error) {}

			// Pass 1 — enemy players in my cell
			try
			{
				for (var avid:* in game.world.avatars)
				{
					var av:* = game.world.avatars[avid];
					if (!av || av.isMyAvatar) continue;

					var theirFrame:String = "";
					try { theirFrame = String(av.objData.strFrame).toLowerCase(); } catch (e:Error) {}
					if (myFrame.length > 0 && theirFrame.length > 0 && theirFrame != myFrame) continue;

					var n:String = "";
					try { n = String(av.objData.strUsername); } catch (e:Error) {}
					if (n.length > 0 && n != "null" && n != "undefined"
						&& !TeammateRoster.isTeammate(n.toLowerCase()))
					{
						_lastAttacker = n;
						return;
					}
				}
			} catch (e:Error) {}

			// Pass 2 — any monster
			try
			{
				for (var mid:* in game.world.monsters)
				{
					var mon:* = game.world.monsters[mid];
					if (!mon) continue;
					var mn:String = "";
					try { mn = String(mon.strMonName); } catch (e:Error) {}
					if (!mn || mn == "null" || mn == "undefined")
						try { mn = String(mon.objData.strMonName); } catch (e2:Error) {}
					if (mn && mn != "null" && mn != "undefined")
					{
						_lastAttacker = mn;
						return;
					}
				}
			} catch (e:Error) {}
		}
	}
}
