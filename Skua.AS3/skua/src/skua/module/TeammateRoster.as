package skua.module
{
	public class TeammateRoster
	{
		private static var _names:Object = {};

		// Add a confirmed teammate by lowercase username.
		public static function add(lcName:String):void
		{
			if (lcName && lcName.length > 0) _names[lcName] = true;
		}

		public static function isTeammate(lcName:String):Boolean
		{
			if (!lcName || lcName.length == 0) return false;
			return _names[lcName] === true;
		}

		public static function remove(lcName:String):void
		{
			if (lcName && lcName.length > 0) delete _names[lcName];
		}

		public static function hasAny():Boolean
		{
			for (var k:String in _names) return true;
			return false;
		}

		// Call when a new match begins (module enable).
		public static function clear():void
		{
			_names = {};
		}
	}
}
