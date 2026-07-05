package skua.module
{
	import flash.geom.ColorTransform;

	public class HitFlash extends Module
	{
		// [rOff, gOff, bOff, ttl]
		private static const STYLES:Array = [
			[255, 255, 255, 12], // 1: White
			[255,   0,   0, 12], // 2: Red
			[255, 120,   0, 12], // 3: Orange
			[  0,  80, 255, 12], // 4: Blue
			[  0, 255,  80, 12], // 5: Green
			[180,   0, 255, 12], // 6: Purple
			[255,   0, 180, 12], // 7: Pink
			[255, 220,   0, 12], // 8: Yellow
			[  0, 220, 255, 12], // 9: Cyan
		];

		private var _myStyle:int    = 0;
		private var _enemyStyle:int = 0;

		private var _myFlash:Object    = null;       // {pmc, ttl, maxTtl, ro, go, bo}
		private var _enemyFlashes:Object = {};        // aid → {pmc, ttl, maxTtl, ro, go, bo}

		private var _myLastHP:Number    = -1;
		private var _enemyLastHP:Object = {};

		public function HitFlash() { super("HitFlash"); }

		public function setMyStyle(n:int):void    { _myStyle    = n; if (n == 0) clearMyFlash(); }
		public function setEnemyStyle(n:int):void { _enemyStyle = n; if (n == 0) clearEnemyFlashes(); }

		override public function onToggle(game:*):void
		{
			if (!enabled)
			{
				clearMyFlash();
				clearEnemyFlashes();
				_myLastHP    = -1;
				_enemyLastHP = {};
			}
		}

		override public function onFrame(game:*):void
		{
			if (_myStyle    > 0) checkMyHit(game);
			if (_enemyStyle > 0) checkEnemyHits(game);
			tickMyFlash();
			tickEnemyFlashes();
		}

		// ── detection ────────────────────────────────────────────────────────

		private function checkMyHit(game:*):void
		{
			var hp:Number;
			try { hp = Number(game.world.myAvatar.dataLeaf.intHP); } catch (e:Error) { return; }
			if (_myLastHP >= 0 && hp < _myLastHP && hp > 0)
			{
				try { triggerMyFlash(game.world.myAvatar.pMC); } catch (e:Error) {}
			}
			_myLastHP = hp;
		}

		private function checkEnemyHits(game:*):void
		{
			var myTeam:* = null;
			try { myTeam = game.world.myAvatar.objData.strTeam; } catch (e:Error) {}

			for (var aid:* in game.world.avatars)
			{
				var av:* = game.world.avatars[aid];
				try
				{
					if (!av || av.isMyAvatar || !av.dataLeaf) continue;
					var isEnemy:Boolean = true;
					try { if (myTeam != null && av.objData.strTeam != null) isEnemy = (myTeam != av.objData.strTeam); }
					catch (e2:Error) {}
					if (!isEnemy) continue;

					var hp:Number   = Number(av.dataLeaf.intHP);
					var prev:Number = (_enemyLastHP[aid] !== undefined) ? Number(_enemyLastHP[aid]) : hp;
					if (hp < prev && hp > 0)
						triggerEnemyFlash(String(aid), av.pMC);
					_enemyLastHP[aid] = hp;
				}
				catch (e:Error) {}
			}
		}

		// ── trigger ──────────────────────────────────────────────────────────

		private function triggerMyFlash(pmc:*):void
		{
			if (_myStyle < 1 || _myStyle > STYLES.length) return;
			var sd:Array = STYLES[_myStyle - 1];
			_myFlash = { pmc: pmc, ttl: int(sd[3]), maxTtl: int(sd[3]), ro: int(sd[0]), go: int(sd[1]), bo: int(sd[2]) };
		}

		private function triggerEnemyFlash(aid:String, pmc:*):void
		{
			if (_enemyStyle < 1 || _enemyStyle > STYLES.length) return;
			var sd:Array = STYLES[_enemyStyle - 1];
			_enemyFlashes[aid] = { pmc: pmc, ttl: int(sd[3]), maxTtl: int(sd[3]), ro: int(sd[0]), go: int(sd[1]), bo: int(sd[2]) };
		}

		// ── tick ─────────────────────────────────────────────────────────────

		private function tickMyFlash():void
		{
			if (_myFlash == null) return;
			_myFlash.ttl--;
			var t:Number = Number(_myFlash.ttl) / Number(_myFlash.maxTtl);
			try
			{
				if (_myFlash.ttl <= 0)
				{
					_myFlash.pmc.transform.colorTransform = new ColorTransform();
					_myFlash = null;
				}
				else
					_myFlash.pmc.transform.colorTransform = new ColorTransform(1, 1, 1, 1, _myFlash.ro * t, _myFlash.go * t, _myFlash.bo * t, 0);
			}
			catch (e:Error) { _myFlash = null; }
		}

		private function tickEnemyFlashes():void
		{
			for (var k:* in _enemyFlashes)
			{
				var f:* = _enemyFlashes[k];
				f.ttl--;
				var t:Number = Number(f.ttl) / Number(f.maxTtl);
				try
				{
					if (f.ttl <= 0)
					{
						f.pmc.transform.colorTransform = new ColorTransform();
						delete _enemyFlashes[k];
					}
					else
						f.pmc.transform.colorTransform = new ColorTransform(1, 1, 1, 1, f.ro * t, f.go * t, f.bo * t, 0);
				}
				catch (e:Error) { delete _enemyFlashes[k]; }
			}
		}

		// ── cleanup ──────────────────────────────────────────────────────────

		private function clearMyFlash():void
		{
			if (_myFlash != null)
			{
				try { _myFlash.pmc.transform.colorTransform = new ColorTransform(); } catch (e:Error) {}
				_myFlash = null;
			}
		}

		private function clearEnemyFlashes():void
		{
			for (var k:* in _enemyFlashes)
			{
				try { _enemyFlashes[k].pmc.transform.colorTransform = new ColorTransform(); } catch (e:Error) {}
			}
			_enemyFlashes = {};
		}
	}
}
