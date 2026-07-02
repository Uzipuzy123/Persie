package skua.module
{
	import flash.display.DisplayObject;
	import flash.display.DisplayObjectContainer;
	import flash.display.MovieClip;
	import flash.utils.Dictionary;

	public class KillParticles extends Module
	{
		private var _hidden:Dictionary;

		public function KillParticles()
		{
			super("KillParticles");
		}

		override public function onToggle(game:*):void
		{
			if (enabled)
			{
				_hidden = new Dictionary(true);
				apply(game);
			}
			else
			{
				restore();
				_hidden = null;
			}
		}

		override public function onFrame(game:*):void
		{
			apply(game);
		}

		private function apply(game:*):void
		{
			try { sweep(game.world.map); } catch (e:Error) {}
		}

		private function restore():void
		{
			if (_hidden == null) return;
			for (var key:* in _hidden)
			{
				try { DisplayObject(key).visible = true; } catch (e:Error) {}
			}
		}

		// Animated leaf clips (totalFrames > 1, no children) are particle sprites.
		// Static clips (totalFrames == 1) are cell pads / backgrounds — leave them alone.
		private function sweep(obj:DisplayObject):void
		{
			try
			{
				if (obj is MovieClip && obj.visible)
				{
					var mc:MovieClip = MovieClip(obj);
					if (mc.totalFrames > 1 && mc.numChildren == 0)
					{
						if (_hidden != null) _hidden[obj] = true;
						obj.visible = false;
						return;
					}
				}

				if (obj is DisplayObjectContainer)
				{
					var doc:DisplayObjectContainer = DisplayObjectContainer(obj);
					for (var i:int = 0; i < doc.numChildren; i++)
						sweep(doc.getChildAt(i));
				}
			}
			catch (e:Error) {}
		}
	}
}
