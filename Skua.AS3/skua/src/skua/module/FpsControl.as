package skua.module
{
	/**
	 * Client-side frame rate override. Same "always-run, driven by a setter"
	 * pattern as SelfHud/ScoreboardSkin/etc — the module stays enabled forever
	 * so onFrame keeps re-applying _fps in case the game's own loader resets
	 * stage.frameRate on scene transitions.
	 */
	public class FpsControl extends Module
	{
		private var _fps:int = 30;

		public function FpsControl() { super("FpsControl"); }

		public function setFps(value:int):void
		{
			_fps = value < 24 ? 24 : (value > 60 ? 60 : value);
		}

		override public function onFrame(game:*):void
		{
			try
			{
				if (game.stage.frameRate != _fps)
					game.stage.frameRate = _fps;
			}
			catch (err:Error) {}
		}
	}
}
