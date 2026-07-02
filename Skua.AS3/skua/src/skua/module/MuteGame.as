package skua.module
{
	import flash.media.SoundMixer;
	import flash.media.SoundTransform;

	public class MuteGame extends Module
	{
		private var _savedVolume:Number = 1;

		public function MuteGame()
		{
			super("MuteGame");
		}

		override public function onToggle(game:*):void
		{
			if (enabled)
			{
				_savedVolume = SoundMixer.soundTransform.volume;
				SoundMixer.soundTransform = new SoundTransform(0);
			}
			else
			{
				SoundMixer.soundTransform = new SoundTransform(_savedVolume > 0 ? _savedVolume : 1);
			}
		}
	}
}
