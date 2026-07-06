package skua.module 
{
	import flash.events.Event;
	import skua.Main;
	
	public class Modules 
	{
		private static var _modules:* = new Object();
		
		public static function getModule(name:String):Module
		{
			return _modules[name];
		}
		
		public static function registerModule(m:Module):void
		{
			_modules[m.name] = m;
		}
		
		public static function enable(name:String):void
		{
			var module:Module = getModule(name);
			if (module != null)
			{
				var toggle:Boolean = !module.enabled;
				module.enabled = true;
				if (toggle)
				{
					module.onToggle(skua.Main.instance.getGame());
				}
			}
		}
		
		public static function disable(name:String):void
		{
			var module:Module = getModule(name);
			if (module != null)
			{
				var toggle:Boolean = module.enabled;
				module.enabled = false;
				if (toggle)
				{
					module.onToggle(skua.Main.instance.getGame());
				}
			}
		}
		
		public static function handleFrame(e:Event):void
		{
			FrameTimeMonitor.tick();
			for (var name:String in _modules)
			{
				var module:Module = _modules[name];
				if (module.enabled)
				{
					module.onFrame(skua.Main.instance.getGame());
				}
			}
		}
		
		public static function init():void
		{
			registerModule(new QuestItemRates());
			registerModule(new HidePlayers());
			registerModule(new DisableCollisions());
			registerModule(new DisableFX());
			registerModule(new ClearFilters());
			registerModule(new StopAnimations());
			registerModule(new KillParticles());
			registerModule(new MuteGame());
			registerModule(new DisableShadows());
			registerModule(new HighlightEnemies());
			registerModule(new HideRoomNumber());
			registerModule(new EnemyHPOverlay());
			registerModule(new MiniMap());
			registerModule(new KillFeed());
			registerModule(new ScoreboardOverlay());
			registerModule(new DebugPanel());
			registerModule(new SkuaSettingsButton());
			registerModule(new OptimizeMap());
			registerModule(new DeathDetector());
			registerModule(new PlayerHPBars());
			registerModule(new KillStreakAnnouncer());
			registerModule(new LowHPFlash());
			registerModule(new HitFlash());
			registerModule(new Vignette());
			registerModule(new SelfOutline());
			registerModule(new KillFlash());
			registerModule(new RevengeKill());
			registerModule(new EnemyOutline());
			registerModule(new AutoQuality());
			registerModule(new FastTarget());

			// FastTarget wires its click listener up inside onToggle(), which only
			// runs on a real enabled-state transition — registerModule() alone
			// never triggers it, so without this call the listener is never attached.
			enable("FastTarget");
		}
	}
}