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
			registerModule(new HideAllHelms());
			registerModule(new HideAllWeapons());
			registerModule(new HideAllCapesLocal());
			registerModule(new HideAllRobes());
			registerModule(new HideRoomNumber());
			registerModule(new EnemyHPOverlay());
			registerModule(new MiniMap());
			registerModule(new KillFeed());
			registerModule(new ScoreboardOverlay());
			registerModule(new DebugPanel());
			registerModule(new SkuaSettingsButton());
			registerModule(new OptimizeMap());
			registerModule(new MapSkin());
			registerModule(new YulgarSkin());
			registerModule(new MapDebug());
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
			registerModule(new SkillOnKeyDown());
			registerModule(new InstantCancelTarget());
			registerModule(new PartyTargetModifier());
			registerModule(new ScoreboardSkin());
			registerModule(new PortalFlash());
			registerModule(new RespawnEffect());
			registerModule(new DisableNativeGlow());
			registerModule(new DisableNativeAnimation());
			registerModule(new AntiCamp());
			registerModule(new NameplateFont());
			registerModule(new TeamFlagReskin());
			registerModule(new SelfHud());
			registerModule(new SkillBarSkin());
			registerModule(new MenuHotkeys());
			registerModule(new IngameMenu());
			registerModule(new FpsControl());
			registerModule(new PingSpoof());
			// Always on at the default -10ms offset — no manual toggle needed.
			enable("PingSpoof");

			// Always on — no manual toggle, skills should just fire on press.
			enable("SkillOnKeyDown");

			// Always on — no manual toggle, Esc should always deselect.
			enable("InstantCancelTarget");

			// Always on — no manual toggle, defaults to Shift (matching the
			// native behavior exactly) until rebound via PVP Keybinds.
			enable("PartyTargetModifier");

			// FastTarget wires its click listener up inside onToggle(), which only
			// runs on a real enabled-state transition — registerModule() alone
			// never triggers it, so without this call the listener is never attached.
			enable("FastTarget");

			// ScoreboardSkin's skin selection is driven by setSkin(), independent of
			// enabled/disabled — it must always run onFrame to react to that call.
			enable("ScoreboardSkin");

			// Same story — TeamFlagReskin's per-team style is driven by
			// setBlueStyle()/setRedStyle(), 0 = off, not a bool enable/disable.
			enable("TeamFlagReskin");

			// Same story — SelfHud's style is driven by setStyle(), 0 = off,
			// not a bool enable/disable.
			enable("SelfHud");

			// Same story — SkillBarSkin's style is driven by setStyle(), 0 = off,
			// not a bool enable/disable.
			enable("SkillBarSkin");

			// MenuHotkeys wires its keyboard listener up inside onToggle(), which
			// only runs on a real enabled-state transition — same reason as
			// FastTarget above.
			enable("MenuHotkeys");

			// Same story — IngameMenu's own keyboard listener (Ctrl+M toggle).
			enable("IngameMenu");

			// Same story — all five are driven by setXStyle()/setColor(), 0 = off,
			// not a bool enable/disable, so onFrame must always run to react to
			// those calls (registerModule() alone leaves enabled = false, meaning
			// handleFrame()'s "if (module.enabled)" gate would otherwise skip
			// onFrame forever regardless of what style gets picked).
			enable("SelfOutline");
			enable("EnemyOutline");
			enable("Vignette");
			enable("HitFlash");
			enable("KillFlash");
			enable("NameplateFont");

			// Same story — FpsControl's rate is driven by setFps(), not a bool
			// enable/disable, and must keep re-applying every frame.
			enable("FpsControl");
		}
	}
}