package skua.module
{
	import flash.display.Sprite;

	// Common surface MapDebug drives — implemented by MapSkin and any
	// dedicated per-map skin module (e.g. YulgarSkin) so calibration works
	// against whichever one currently has a room picture up, without
	// MapDebug needing to know about each module by name.
	public interface ISkinModule
	{
		function getContainer():Sprite;
	}
}
