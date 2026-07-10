package skua.module
{
	import flash.events.KeyboardEvent;
	import flash.ui.Keyboard;

	/**
	 * Self-contained hotkey cycling for the visual reskin styles (SelfHud,
	 * SkillBarSkin). These need no host application at all to toggle — both
	 * modules' setStyle() is plain AS3 with no ExternalInterface dependency,
	 * so a keyboard listener living entirely inside this SWF can drive them
	 * directly, the same way a from-scratch client would build its own
	 * in-SWF menu toggles rather than relying on an external UI.
	 *
	 * Ctrl-modified so normal gameplay keys (number-row skills, WASD, etc.)
	 * are never intercepted.
	 */
	public class MenuHotkeys extends Module
	{
		private static const SELF_HUD_STYLE_COUNT:int  = 10; // STYLE_OFF..STYLE_ORB
		private static const SKILL_BAR_STYLE_COUNT:int = 2;  // STYLE_OFF..STYLE_HEXGRID

		private var _selfHudIndex:int = 0;
		private var _skillBarIndex:int = 0;

		public function MenuHotkeys() { super("MenuHotkeys"); }

		override public function onToggle(game:*):void
		{
			if (enabled)
				game.stage.addEventListener(KeyboardEvent.KEY_UP, onKeyUp);
			else
				game.stage.removeEventListener(KeyboardEvent.KEY_UP, onKeyUp);
		}

		private function onKeyUp(e:KeyboardEvent):void
		{
			try
			{
				if (!e.ctrlKey) return;

				if (e.keyCode == Keyboard.H)
				{
					_selfHudIndex = (_selfHudIndex + 1) % SELF_HUD_STYLE_COUNT;
					var selfHud:* = Modules.getModule("SelfHud");
					if (selfHud) selfHud.setStyle(_selfHudIndex);
				}
				else if (e.keyCode == Keyboard.K)
				{
					_skillBarIndex = (_skillBarIndex + 1) % SKILL_BAR_STYLE_COUNT;
					var skillBar:* = Modules.getModule("SkillBarSkin");
					if (skillBar) skillBar.setStyle(_skillBarIndex);
				}
			}
			catch (err:Error) {}
		}
	}
}
