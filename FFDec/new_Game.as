package
{
   import fl.motion.Color;
   import flash.display.Loader;
   import flash.display.MovieClip;
   import flash.events.Event;
   import flash.events.IOErrorEvent;
   import flash.display.DisplayObject;
   import flash.display.Shape;
   import flash.geom.ColorTransform;
   import flash.geom.Point;
   import flash.geom.Rectangle;
   import flash.net.URLRequest;
   import flash.system.ApplicationDomain;
   import flash.system.LoaderContext;
   import flash.utils.getDefinitionByName;

   public dynamic class Game extends MovieClip
   {
      // Stubs required by mcSkel's overridden gotoAndPlay()/handleAnimEvent(),
      // which read these directly off `parent` (normally the real in-game
      // AvatarMC) — mcSkel crashes on its very first frame without them.
      public var pAV:Object = {morphMC: null};
      public var AnimEvent:Object = {};

      private var rig:mcSkel;
      private var ldr:Loader;
      private var serverFilePath:String = "";
      private var objData:Object;
      private var strGender:String;
      private var baseX:Number;
      private var baseY:Number;
      private var feetLocalX:Number = 0; // rig's registration point isn't at the feet (confirmed by the earlier kneel attempt) —
      private var feetLocalY:Number = 0; // these are measured once from actual bounds so any rotation/scale can pivot around the real feet

      // hip/thigh/shin/foot (and shoulder/hand) are siblings, not nested
      // parent-child — but each one's own registration point IS at its real
      // joint (standard rigging practice), so rotating e.g. frontthigh
      // already pivots correctly at the hip. The disconnect was always the
      // DOWNSTREAM part (frontshin) staying put instead of following. These
      // record, once at the idle pose (before any custom rotation), exactly
      // where each downstream part's origin sits relative to its upstream
      // part's own coordinate space — then repositionAtJoint() below can
      // reattach it correctly after the upstream part rotates, using real
      // measured geometry instead of guessed pixel offsets.
      private var kneeOffsetFront:Point;
      private var ankleOffsetFront:Point;
      private var kneeOffsetBack:Point;
      private var ankleOffsetBack:Point;
      private var handOffsetFront:Point;
      private var handOffsetBack:Point;

      // Neither rotating frontshoulder directly (its own pivot isn't at the
      // real joint) nor free-floating fronthand's position (no joint at all)
      // looked right. Third approach: treat frontshoulder as the FIXED
      // anchor (like hip is for thigh) and swing fronthand *around that
      // fixed point* using explicit rotation math — same trick as toppling
      // the whole rig around the feet, just for the shoulder-hand joint.
      private var handOffsetFrontX:Number; // fronthand's resting position, in RIG space, relative to frontshoulder's own fixed position
      private var handOffsetFrontY:Number;
      private var handOffsetBackX:Number;
      private var handOffsetBackY:Number;

      private function jointOffset(upstream:DisplayObject, downstream:DisplayObject) : Point
      {
         return upstream.globalToLocal(downstream.localToGlobal(new Point(0, 0)));
      }

      private function repositionAtJoint(upstream:DisplayObject, downstream:DisplayObject, offset:Point) : void
      {
         var g:Point = upstream.localToGlobal(offset);
         var l:Point = this.rig.globalToLocal(g);
         downstream.x = l.x;
         downstream.y = l.y;
      }

      // Named parts the DOM/SVG rig rebuild extracts as individual images —
      // cape/weapon/robe deliberately excluded (kept out of scope per
      // earlier request). Used by applyIsolation() below for calibration
      // captures: one part visible at a time, so a single Ruffle capture
      // shows exactly that part's art with a known-color marker at its
      // pivot, letting the JS side measure both its crop rectangle (alpha
      // bounding box) and its true rotation pivot (marker centroid) once,
      // instead of guessing either from how things look mid-animation.
      private static const RIG_PARTS:Array = ["head", "chest", "hip",
         "frontshoulder", "backshoulder", "fronthand", "backhand",
         "frontthigh", "backthigh", "frontshin", "backshin", "idlefoot", "backfoot"];

      // A colored dot at (0,0) in a part's own local space shows exactly
      // where Flash thinks that part's registration point (rotation pivot)
      // is, instead of guessing from how it looks when rotated.
      private function markJoint(part:MovieClip, color:uint) : void
      {
         var dot:Shape = new Shape();
         // Black outline ring first so the bright fill reads against any
         // background color, then a much bigger fill, then a thick crosshair
         // extending well past the part's own art so it's visible even if
         // partly covered by gear layered on top.
         dot.graphics.lineStyle(3, 0x000000, 1);
         dot.graphics.beginFill(color, 1);
         dot.graphics.drawCircle(0, 0, 14);
         dot.graphics.endFill();
         dot.graphics.lineStyle(4, color, 1);
         dot.graphics.moveTo(-30, 0);
         dot.graphics.lineTo(30, 0);
         dot.graphics.moveTo(0, -30);
         dot.graphics.lineTo(0, 30);
         part.addChild(dot);
      }

      // Custom crying effect — not a baked effect, just simple vector-drawn
      // teardrop shapes added directly as CHILDREN of head (not a sibling),
      // so they automatically follow its rotation/position for free. Each
      // one drips down and fades, then resets to the top for a looping cry.
      private var tears:Array = [];

      private function createTears() : void
      {
         for (var i:int = 0; i < 2; i++)
         {
            var tear:Shape = new Shape();
            tear.graphics.beginFill(0x55CCFF, 0.9);
            tear.graphics.moveTo(0, -3);
            tear.graphics.curveTo(2.2, 1, 0, 4);
            tear.graphics.curveTo(-2.2, 1, 0, -3);
            tear.graphics.endFill();
            tear.x = (i == 0) ? -7 : 7;
            tear.y = -18 - i * 8;
            this.rig.head.addChild(tear);
            this.tears.push(tear);
         }
      }

      private function updateTears() : void
      {
         for (var i:int = 0; i < this.tears.length; i++)
         {
            var tear:Shape = this.tears[i];
            tear.y += 0.7;
            tear.alpha = Math.max(0, 1 - (tear.y + 18) / 30);
            if (tear.y > 14)
            {
               tear.y = -18 - Math.random() * 6;
               tear.alpha = 1;
            }
         }
      }

      public function Game()
      {
         super();
         // We replaced the document class but the root timeline itself still
         // has whatever frames the real game's boot/loading sequence baked in
         // (this SWF's own frameCount, independent of our code) — without an
         // explicit stop() it keeps auto-playing and looping through them
         // forever, periodically placing/removing objects (a loading-screen
         // background layer among them) on top of our added child. That's
         // what was flashing solid black every couple seconds.
         stop();
         this.objData = root.loaderInfo.parameters;
         // [\w.]+ stops at the first ":" — silently truncates a port number
         // (e.g. "http://localhost:3000" -> "http://localhost"), which then
         // sends every gear load to the wrong port. Match up to the next "/"
         // instead so host:port survives intact.
         var reg:RegExp = /https?:\/\/[^\/]+/i;
         this.serverFilePath = String(root.loaderInfo.url).match(reg) + "/game/gamefiles/";

         // Solid, guaranteed-static backdrop, added FIRST so it sits behind
         // everything. The stage's own scenic background art turned out to
         // have at least one element that keeps animating independently of
         // our stop() (not on the root timeline), so two captures taken a
         // moment apart (as the DOM rig rebuild's baseline-diff masking
         // does) could show genuinely different backdrop pixels no
         // color-distance threshold could paper over. Painting our own flat
         // color over it makes the backdrop deterministic by construction.
         //
         // Went cyan -> magenta after a real collision (Prime Bank Pet's
         // teal-toned aura shared cyan's hue family), then found ANOTHER
         // collision the other direction (Prime's white/warm-tinted glow
         // effects — halo ring, sword shine, cape/pet highlights — share
         // enough of magenta's hue to trip the same math). Single flat key
         // colors are whack-a-mole: whichever one is picked, some AQW glow
         // effect's own art shares its hue closely enough to break the
         // excess/de-spill formula. Real fix is triangulation (two-backdrop
         // difference) matting — this needs the SAME character rendered
         // twice against two DIFFERENT known backdrop colors, so the JS
         // side can solve for true alpha/color directly instead of assuming
         // one background hue. bgColorOverride lets JS pick which backdrop
         // color this particular load uses, defaulting to magenta so any
         // caller that doesn't pass it keeps working unchanged.
         var bgColor:uint = 0xFF00FF;
         if (this.objData.bgColorOverride != undefined && String(this.objData.bgColorOverride) != "")
         {
            bgColor = uint(parseInt(String(this.objData.bgColorOverride), 16));
         }
         var backdrop:Shape = new Shape();
         backdrop.graphics.beginFill(bgColor, 1);
         backdrop.graphics.drawRect(0, 0, 960, 550);
         backdrop.graphics.endFill();
         addChild(backdrop);

         this.rig = new mcSkel();
         this.rig.x = 160; // nudged right — the crop box (0-320, center 160) had the character sitting left of center at 130
         this.rig.y = 300;
         this.baseX = this.rig.x;
         this.baseY = this.rig.y;
         addChild(this.rig);
         this.hideOptionalParts();
         // Name/guild text used to be added here as TextFields, but
         // getBounds()-based positioning against the rig/head never lined
         // up with the actual visible art (kept measuring some invisible
         // element far above the head, leaving a huge gap) — moved to the
         // JS/Canvas side instead, drawn after cropping where the character
         // bounds are already known exactly. See renderBotStatic.html.

         // Ready beacon: a fixed bright square at a known stage position,
         // invisible until armor has actually finished its NETWORK load.
         // Gear comes from the live game's CDN (the same WAF-flaky fetch
         // documented in server.js) — a fixed capture delay isn't reliable,
         // so JS polls for this instead of guessing how long the load will
         // take. Was green (0x00FF00) — moved to orange since green is now
         // also a valid backdrop color (bgColorOverride) for dual-key
         // matting, and a green beacon would vanish into a green backdrop.
         this.readyBeacon = new Shape();
         this.readyBeacon.graphics.beginFill(0xFFA500, 1);
         this.readyBeacon.graphics.drawRect(0, 0, 24, 24);
         this.readyBeacon.graphics.endFill();
         this.readyBeacon.x = 0;
         this.readyBeacon.y = 0;
         this.readyBeacon.visible = false;
         addChild(this.readyBeacon);

         this.ldr = new Loader();
         this.loadArmor();
      }

      private var readyBeacon:Shape;

      // Mirrors the real AvatarMC's hideOptionalParts()/drawHitBox(): mcSkel
      // ships with these visible/filled by default (a pvp team flag, and a
      // hitbox shape meant only for hit-testing math, drawn with a real black
      // fill in the authored asset) — the real game immediately hides/clears
      // them before ever showing an avatar. Skipping this step is what was
      // showing as a stray flag and a solid black duplicate behind the rig.
      private function hideOptionalParts() : void
      {
         // Same two lists the real AvatarMC hides on startup — the second
         // one (weapon/off-hand/shield) is what was showing as the stray
         // black fist/shield shape behind the character: those slots ship
         // with default placeholder art too, only "weapon" gets explicitly
         // re-shown once a real weapon finishes loading (onLoadWeaponComplete).
         var hidden:Array = ["cape", "backhair", "robe", "backrobe", "pvpFlag",
                              "weapon", "weaponOff", "weaponFist", "weaponFistOff", "shield"];
         for each (var partName:String in hidden)
         {
            if (this.rig[partName] != null) this.rig[partName].visible = false;
         }
         this.rig.hitbox.graphics.clear();
      }

      private function get armorFile() : String { return this.objData.strCustArmorFile || this.objData.strClassFile; }
      private function get armorLink() : String { return this.objData.strCustArmorLink || this.objData.strClassLink; }
      private function get helmFile() : String { return this.objData.strCustHelmFile || this.objData.strHelmFile; }
      private function get helmLink() : String { return this.objData.strCustHelmLink || this.objData.strHelmLink; }
      private function get weaponFile() : String { return this.objData.strCustWeaponFile || this.objData.strWeaponFile; }
      private function get weaponLink() : String { return this.objData.strCustWeaponLink || this.objData.strWeaponLink; }
      private function get capeFile() : String { return this.objData.strCustCapeFile || this.objData.strCapeFile; }
      private function get capeLink() : String { return this.objData.strCustCapeLink || this.objData.strCapeLink; }
      private function get petFile() : String { return this.objData.strPetFile; }
      private function get petLink() : String { return this.objData.strPetLink; }

      // How many of the optional parallel loads (helm/weapon/cape) are still
      // in flight — the ready beacon used to fire right after armor alone,
      // which was fine when those slots stayed hidden, but now that weapon/
      // cape actually render, firing early would let the bot capture a
      // frame before they've visually appeared. Armor itself doesn't count
      // here (onLoadSkinComplete already only runs once it's done).
      private var pendingLoads:int = 0;

      private function loadArmor() : void
      {
         this.ldr.load(new URLRequest(this.serverFilePath + "classes/" + this.objData.strGender + "/" + this.armorFile), new LoaderContext(false, ApplicationDomain.currentDomain));
         this.ldr.contentLoaderInfo.addEventListener(Event.COMPLETE, this.onLoadSkinComplete);
         this.ldr.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR, this.ioErrorHandler);
      }

      private function onLoadSkinComplete(evt:Event) : void
      {
         var AssetClass:Class = null;
         this.strGender = this.objData.strGender;
         try
         {
            AssetClass = getDefinitionByName(this.armorLink + this.strGender + "Head") as Class;
            this.rig.head.removeChildAt(0);
            this.rig.head.addChildAt(new AssetClass(), 0);
         }
         catch(err:Error)
         {
            AssetClass = getDefinitionByName("mcHead" + this.strGender) as Class;
            this.rig.head.removeChildAt(0);
            this.rig.head.addChildAt(new AssetClass(), 0);
         }
         AssetClass = getDefinitionByName(this.armorLink + this.strGender + "Chest") as Class;
         this.rig.chest.removeChildAt(0);
         this.rig.chest.addChild(new AssetClass());
         AssetClass = getDefinitionByName(this.armorLink + this.strGender + "Hip") as Class;
         this.rig.hip.removeChildAt(0);
         this.rig.hip.addChild(new AssetClass());
         AssetClass = getDefinitionByName(this.armorLink + this.strGender + "FootIdle") as Class;
         this.rig.idlefoot.removeChildAt(0);
         this.rig.idlefoot.addChild(new AssetClass());
         AssetClass = getDefinitionByName(this.armorLink + this.strGender + "Foot") as Class;
         this.rig.backfoot.removeChildAt(0);
         this.rig.backfoot.addChild(new AssetClass());
         AssetClass = getDefinitionByName(this.armorLink + this.strGender + "Shoulder") as Class;
         this.rig.frontshoulder.removeChildAt(0);
         this.rig.frontshoulder.addChild(new AssetClass());
         this.rig.backshoulder.removeChildAt(0);
         this.rig.backshoulder.addChild(new AssetClass());
         AssetClass = getDefinitionByName(this.armorLink + this.strGender + "Hand") as Class;
         this.rig.fronthand.removeChildAt(0);
         this.rig.fronthand.addChildAt(new AssetClass(), 0);
         this.rig.backhand.removeChildAt(0);
         this.rig.backhand.addChildAt(new AssetClass(), 0);
         var drk:Color = new Color();
         drk.brightness = -1;
         this.rig.backhand.getChildAt(0).transform.colorTransform = drk;
         AssetClass = getDefinitionByName(this.armorLink + this.strGender + "Thigh") as Class;
         this.rig.frontthigh.removeChildAt(0);
         this.rig.frontthigh.addChild(new AssetClass());
         this.rig.backthigh.removeChildAt(0);
         this.rig.backthigh.addChild(new AssetClass());
         AssetClass = getDefinitionByName(this.armorLink + this.strGender + "Shin") as Class;
         this.rig.frontshin.removeChildAt(0);
         this.rig.frontshin.addChild(new AssetClass());
         this.rig.backshin.removeChildAt(0);
         this.rig.backshin.addChild(new AssetClass());
         try
         {
            AssetClass = getDefinitionByName(this.armorLink + this.strGender + "Robe") as Class;
            this.rig.robe.removeChildAt(0);
            this.rig.robe.addChild(new AssetClass());
            this.rig.robe.visible = true;
         }
         catch(err:Error) {}
         try
         {
            AssetClass = getDefinitionByName(this.armorLink + this.strGender + "RobeBack") as Class;
            this.rig.backrobe.removeChildAt(0);
            this.rig.backrobe.addChild(new AssetClass());
            this.rig.backrobe.visible = true;
         }
         catch(err:Error) {}

         if (this.objData.strHelmFile != "none" || this.objData.strCustHelmName != undefined)
         {
            this.pendingLoads++;
            this.loadHelm();
         }
         if (this.objData.strWeaponFile != "none" && this.weaponFile != "none")
         {
            this.pendingLoads++;
            this.loadWeapon();
         }
         if (this.objData.strCapeFile != "none" && this.capeFile != "none")
         {
            this.pendingLoads++;
            this.loadCape();
         }
         if (this.petFile != "none" && this.petFile != undefined && this.petFile != "")
         {
            this.pendingLoads++;
            this.loadPet();
         }

         // Armor (the main body — everything RIG_PARTS cares about) has now
         // actually finished its network load. If nothing else is pending
         // (isolation/calibration mode, or a bare character with no helm/
         // weapon/cape/pet), the beacon can fire immediately; otherwise
         // checkAllLoaded() fires it once every parallel load above
         // actually finishes, so a bot capture never catches gear mid-load.
         this.checkAllLoaded();

         if (this.objData.isolatePart != undefined && this.objData.isolatePart != "")
         {
            this.applyIsolation();
         }
         else
         {
            this.applyResult();
         }
      }

      // Calibration mode for the DOM/SVG rig rebuild — hides every named
      // part except the one requested (objData.isolatePart), optionally
      // marking its pivot (objData.calibrate), and settles at Idle with no
      // emote running. Not used for normal per-player rendering.
      private function applyIsolation() : void
      {
         this.rig.gotoAndStop("Idle");
         var isolate:String = String(this.objData.isolatePart);
         for each (var p:String in RIG_PARTS)
         {
            if (this.rig[p] != null) this.rig[p].visible = (p == isolate);
         }
         if (String(this.objData.calibrate) == "true" && this.rig[isolate] != null)
         {
            // Was magenta, then green — both are now valid backdrop colors
            // (bgColorOverride, for dual-key matting), so a marker in
            // either would risk vanishing into a same-colored backdrop.
            // Blue isn't used as a backdrop option.
            this.markJoint(this.rig[isolate] as MovieClip, 0x0000FF);
         }
      }

      private function loadHelm() : void
      {
         var hldr:Loader = new Loader();
         hldr.load(new URLRequest(this.serverFilePath + this.helmFile), new LoaderContext(false, ApplicationDomain.currentDomain));
         hldr.contentLoaderInfo.addEventListener(Event.COMPLETE, this.onLoadHelmComplete, false, 0, true);
      }

      private function onLoadHelmComplete(e:Event) : void
      {
         var AssetClass:Class = getDefinitionByName(this.helmLink) as Class;
         this.rig.head.helm.removeChildAt(0);
         this.rig.head.helm.addChild(new AssetClass());
         this.rig.head.helm.visible = true;
         this.rig.head.hair.visible = false;
         this.pendingLoads--;
         this.checkAllLoaded();
      }

      // Some weapon items (items/swords/axe05.swf etc.) ship as a single
      // standalone SWF with no "Export for ActionScript" linkage at all —
      // confirmed empty strWeaponLink/strCustWeaponLink for those, and the
      // loaded movie's own root content IS the weapon art directly. BUT
      // this isn't universal: "Prime's Star Striker" (StarStrikerr1.swf)
      // decompiles to a BLANK root timeline with its actual sword art only
      // reachable via SymbolClass linkage "StarStriker" — same pattern as
      // cape/helm/pet — and its strCustWeaponLink is non-empty ("StarStriker"),
      // confirming which pattern a given weapon uses. Root cause of a bug
      // where Prime rendered with no visible weapon at all: e.target.content
      // was blank for this weapon type. Branch on whether a link name
      // exists rather than assuming one pattern for every weapon.
      private function loadWeapon() : void
      {
         var wldr:Loader = new Loader();
         wldr.load(new URLRequest(this.serverFilePath + this.weaponFile), new LoaderContext(false, ApplicationDomain.currentDomain));
         wldr.contentLoaderInfo.addEventListener(Event.COMPLETE, this.onLoadWeaponComplete, false, 0, true);
         wldr.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR, this.onLoadFailSkip, false, 0, true);
      }

      private function onLoadWeaponComplete(e:Event) : void
      {
         this.rig.weapon.removeChildAt(0);
         if (this.weaponLink != null && this.weaponLink != "")
         {
            var WeaponClass:Class = getDefinitionByName(this.weaponLink) as Class;
            this.rig.weapon.addChild(new WeaponClass());
         }
         else
         {
            this.rig.weapon.addChild(e.target.content);
         }
         this.rig.weapon.visible = true;
         this.pendingLoads--;
         this.checkAllLoaded();
      }

      // Capes DO carry a real linkage name (strCapeLink/strCustCapeLink),
      // same convention as helm — separate standalone file, named symbol.
      private function loadCape() : void
      {
         var cldr:Loader = new Loader();
         cldr.load(new URLRequest(this.serverFilePath + this.capeFile), new LoaderContext(false, ApplicationDomain.currentDomain));
         cldr.contentLoaderInfo.addEventListener(Event.COMPLETE, this.onLoadCapeComplete, false, 0, true);
         cldr.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR, this.onLoadFailSkip, false, 0, true);
      }

      private function onLoadCapeComplete(e:Event) : void
      {
         var AssetClass:Class = getDefinitionByName(this.capeLink) as Class;
         this.rig.cape.removeChildAt(0);
         this.rig.cape.addChild(new AssetClass());
         this.rig.cape.visible = true;
         this.pendingLoads--;
         this.checkAllLoaded();
      }

      // Pets aren't part of mcSkel at all (no rig slot for one, unlike
      // weapon/cape) — in the real game they're a separate companion sprite
      // that floats near the player, so here they're just an independent
      // display object added as our own sibling of the rig, positioned near
      // its feet rather than attached to any rig part. Confirmed via
      // decompiling an actual pet swf (ShadowWraith.swf): its root timeline
      // is blank — the real art is a library symbol under a SymbolClass
      // linkage name, same as cape/helm, NOT a directly-displayable loaded
      // root like weapon. addChild(loader) alone rendered nothing.
      private var petLoader:Loader;

      private function loadPet() : void
      {
         this.petLoader = new Loader();
         this.petLoader.load(new URLRequest(this.serverFilePath + this.petFile), new LoaderContext(false, ApplicationDomain.currentDomain));
         this.petLoader.contentLoaderInfo.addEventListener(Event.COMPLETE, this.onLoadPetComplete, false, 0, true);
         this.petLoader.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR, this.onLoadFailSkip, false, 0, true);
      }

      private function onLoadPetComplete(e:Event) : void
      {
         // First guess (baseX+90, baseY+40) put the pet low and forward,
         // overlapping the character's own legs/hip. Moved to the opposite
         // side from the weapon hand at chest height, but (baseX-100,
         // baseY-70) was then confirmed too FAR from the character against
         // a real reference capture — pulled in closer.
         var PetClass:Class = getDefinitionByName(this.petLink) as Class;
         var petInstance:DisplayObject = new PetClass() as DisplayObject;

         // Downsize oversized pets: pet art is authored at whatever scale
         // its own artist chose, with no guarantee it's proportional to
         // the character rig at all. "Prime Bank Pet" in particular has a
         // wide wingspan (~245x154 native units, confirmed via a raw
         // pixel-level capture) that reads as visually dominating next to
         // the character.
         var typicalCharacterHeight:Number = 230;
         var typicalCharacterWidth:Number = 150;

         // getBounds() is NOT a reliable measure of a pet's actual visual
         // footprint — confirmed via trace(): for this exact pet it
         // reported 107x107 while the true rendered pixels measure
         // 245x154 (~2.3x wider than getBounds() claims). Almost certainly
         // glow/blur filter bleed, which extends what's actually painted
         // well past the underlying shape's geometric bounds; Flash has no
         // "bounds including filter bleed" API to fall back on. This bit
         // BOTH the sizing check AND the shadow's position (which used
         // getBounds().bottom) — the shadow ended up correctly grounded at
         // the CHARACTER's feet level by coincidence, but far below where
         // the pet's own art actually stops, reading as "floating".
         //
         // Storing the FULL local bounding box (not just width/height) for
         // known-bad pets fixes both at once: same raw pixel-scan capture
         // used to find the true 245x154 size also gives the box's actual
         // offset from the pet's own registration point, so scale AND
         // shadow placement both derive from real measured geometry
         // instead of asking getBounds() (proven wrong) a second time.
         var knownPetLocalBounds:Object = { "PrimePetBank": { minX: -76, minY: -95, maxX: 169, maxY: 59 } };
         var petLocalBounds:Rectangle;
         if (knownPetLocalBounds[this.petLink] != undefined)
         {
            var kb:Object = knownPetLocalBounds[this.petLink];
            petLocalBounds = new Rectangle(Number(kb.minX), Number(kb.minY), Number(kb.maxX) - Number(kb.minX), Number(kb.maxY) - Number(kb.minY));
         }
         else
         {
            // Best-effort fallback for any pet not in the override table —
            // measuring across every frame (not just frame 1) at least
            // catches a reveal/spawn animation that isn't fully expanded
            // on its default frame, even though it can't correct for
            // filter-bleed underestimation.
            petLocalBounds = petInstance.getBounds(petInstance);
            var petMC:MovieClip = petInstance as MovieClip;
            if (petMC != null && petMC.totalFrames > 1)
            {
               var sampleFrame:int;
               for (sampleFrame = 2; sampleFrame <= petMC.totalFrames; sampleFrame++)
               {
                  petMC.gotoAndStop(sampleFrame);
                  var sampledBounds:Rectangle = petInstance.getBounds(petInstance);
                  petLocalBounds = petLocalBounds.union(sampledBounds);
               }
               petMC.gotoAndStop(1);
            }
         }

         var maxPetHeight:Number = typicalCharacterHeight * 0.7;
         var maxPetWidth:Number = typicalCharacterWidth;
         var scaleForHeight:Number = petLocalBounds.height > maxPetHeight ? maxPetHeight / petLocalBounds.height : 1;
         var scaleForWidth:Number = petLocalBounds.width > maxPetWidth ? maxPetWidth / petLocalBounds.width : 1;
         // Fit-to-character-size scale, then a flat 1.5x on top — pets read
         // as too small/insignificant next to the character at the bare
         // fit-to-bounds size. The JS-side repositioning (renderBotStatic/
         // Animated.html) measures the pet's real rendered footprint via
         // pixel blob detection, not this number directly, so it
         // automatically adapts to whatever size actually comes out here.
         var PET_SIZE_MULTIPLIER:Number = 1.5;
         var petScale:Number = Math.min(scaleForHeight, scaleForWidth) * PET_SIZE_MULTIPLIER;
         petInstance.scaleX = petScale;
         petInstance.scaleY = petScale;

         petInstance.x = this.baseX - 65;
         petInstance.y = this.baseY - 50;

         addChild(petInstance);

         // Ground-contact shadow: confirmed via decompiling the pet's own
         // SWF (pet-PrimePetBank.swf) that NOTHING resembling a shadow is
         // part of the pet's exported symbol itself — in the real game this
         // is drawn by a separate, generic per-character/pet shadow-caster
         // in the engine, not baked into each individual gear asset, so our
         // custom rig (which only loads the specific equipped-item SWFs)
         // never reproduced it. Positioned from petLocalBounds (real
         // measured geometry for known pets, best-effort getBounds() for
         // others) transformed by the SAME petScale/position just applied,
         // rather than re-querying getBounds() on the positioned instance.
         var shadowScale:Number = Math.min(petScale, 1);
         var shadowCenterXLocal:Number = (petLocalBounds.left + petLocalBounds.right) / 2;
         var shadow:Shape = new Shape();
         shadow.graphics.beginFill(0x000000, 0.35);
         shadow.graphics.drawEllipse(-38 * shadowScale, -12 * shadowScale, 76 * shadowScale, 24 * shadowScale);
         shadow.graphics.endFill();
         shadow.x = petInstance.x + shadowCenterXLocal * petScale;
         shadow.y = petInstance.y + petLocalBounds.bottom * petScale - 8 * shadowScale;
         addChildAt(shadow, getChildIndex(petInstance));
         this.pendingLoads--;
         this.checkAllLoaded();
      }

      // Shared by weapon/cape's error listeners — same "don't hang the
      // beacon on a broken/missing file" reasoning as onLoadPetError below,
      // just generic since neither needs its own cleanup beyond the counter.
      private function onLoadFailSkip(e:IOErrorEvent) : void
      {
         this.pendingLoads--;
         this.checkAllLoaded();
      }

      private function checkAllLoaded() : void
      {
         if (this.pendingLoads <= 0) this.readyBeacon.visible = true;
      }

      private var emoteMode:String = "none";
      private var emoteFrame:int = 0;

      private function applyResult() : void
      {
         var result:String = String(this.objData.matchResult);
         // Freeze on the rig's own Idle pose and drive our own custom emote
         // on top of it frame-by-frame for both outcomes.
         this.rig.gotoAndStop("Idle");
         if (result == "win" || result == "lose")
         {
            // frontshoulder itself is never rotated (its own pivot isn't
            // trustworthy — confirmed repeatedly), so fronthand instead
            // swings AROUND frontshoulder's fixed position using explicit
            // trig, same technique proven fine for the loser's kick. At
            // idle, frontshoulder has rotation 0, so a plain coordinate
            // subtraction gives exactly the resting offset to rotate.
            this.handOffsetFrontX = this.rig.fronthand.x - this.rig.frontshoulder.x;
            this.handOffsetFrontY = this.rig.fronthand.y - this.rig.frontshoulder.y;

            if (result == "lose")
            {
               var b:Rectangle = this.rig.getBounds(this);
               this.feetLocalX = (b.left + b.right) / 2 - this.baseX;
               this.feetLocalY = b.bottom - this.baseY;
               this.kneeOffsetFront  = this.jointOffset(this.rig.frontthigh, this.rig.frontshin);
               this.ankleOffsetFront = this.jointOffset(this.rig.frontshin, this.rig.idlefoot);
               this.kneeOffsetBack   = this.jointOffset(this.rig.backthigh, this.rig.backshin);
               this.ankleOffsetBack  = this.jointOffset(this.rig.backshin, this.rig.backfoot);
               this.handOffsetFront  = this.jointOffset(this.rig.frontshoulder, this.rig.fronthand);
               this.handOffsetBack   = this.jointOffset(this.rig.backshoulder, this.rig.backhand);
               this.handOffsetBackX  = this.rig.backhand.x - this.rig.backshoulder.x;
               this.handOffsetBackY  = this.rig.backhand.y - this.rig.backshoulder.y;
            }

            this.emoteMode = result;
            this.emoteFrame = 0;
            addEventListener(Event.ENTER_FRAME, this.onEmoteFrame);
         }
      }

      // Loser only now — winner plays the real baked "Dance" label (see
      // applyResult()) instead of a custom emote. A one-shot ease into a
      // slumped lean/topple that holds once it gets there, darkening/
      // desaturating to sell the mood, then a kick/flail using the same
      // joint-following system (rotate the upstream part, reposition the
      // downstream part to its measured joint) that keeps limbs attached.
      private function onEmoteFrame(e:Event) : void
      {
         this.emoteFrame++;
         if (this.emoteMode == "win")
         {
            var t3:Number = this.emoteFrame;
            var phase:Number = t3 * 0.22;
            var bounce:Number = Math.sin(phase);

            // Whole-body bounce/lean + head bob — always safe, since these
            // move the rig/head themselves rather than trusting any
            // sibling part's pivot.
            this.rig.rotation = bounce * 4;
            this.rig.y = this.baseY - Math.abs(bounce) * 8;
            this.rig.head.rotation = -bounce * 9;

            // Front hand raised and waving in a cheer — frontshoulder
            // itself is never rotated (its pivot isn't trustworthy), the
            // hand instead swings AROUND frontshoulder's fixed position via
            // explicit trig, same technique already proven fine for the
            // loser's kick.
            var waveAngle:Number = -50 + Math.sin(phase * 1.5) * 20;
            var waveRad:Number = waveAngle * Math.PI / 180;
            this.rig.fronthand.x = this.rig.frontshoulder.x + (this.handOffsetFrontX * Math.cos(waveRad) - this.handOffsetFrontY * Math.sin(waveRad));
            this.rig.fronthand.y = this.rig.frontshoulder.y + (this.handOffsetFrontX * Math.sin(waveRad) + this.handOffsetFrontY * Math.cos(waveRad));
            this.rig.fronthand.rotation = waveAngle;
         }
         else if (this.emoteMode == "lose")
         {
            var t:Number = this.emoteFrame;

            // Fully custom, no baked animation this time. Real constraint:
            // hip/thigh/shin/foot/hand are disconnected siblings, so there's
            // no clean way to bend a real knee/elbow — only whole-rig
            // transforms keep every part's relative position intact. So the
            // "fall over" is the whole rig toppling as one rigid unit
            // (rotating around the actual feet position, measured via
            // getBounds since the registration point isn't there — same
            // fix as the earlier kneel attempt), and the "kicking" is small
            // independent wiggles on the limb pieces — kept deliberately
            // subtle since larger swings are what caused visible gaps
            // between limbs on the earlier kneel attempt.

            // Phase 1 (0-20): look down, still standing.
            var p1:Number = Math.min(t / 20, 1);
            this.rig.head.rotation = (1 - Math.pow(1 - p1, 3)) * 25;

            // Phase 2 (15-45, overlapping phase 1's tail): topple onto their
            // back, pivoting around the feet so they don't slide off-position.
            var p2:Number = Math.max(0, Math.min((t - 15) / 30, 1));
            var e2:Number = 1 - Math.pow(1 - p2, 3);
            var angleDeg:Number = e2 * 80; // full collapse — crop widened on the JS side to fit it instead of cutting the fall short
            var rad:Number = angleDeg * Math.PI / 180;
            var rotX:Number = this.feetLocalX * Math.cos(rad) - this.feetLocalY * Math.sin(rad);
            var rotY:Number = this.feetLocalX * Math.sin(rad) + this.feetLocalY * Math.cos(rad);
            this.rig.rotation = angleDeg;
            this.rig.x = this.baseX + this.feetLocalX - rotX;
            this.rig.y = this.baseY + this.feetLocalY - rotY;

            // Phase 3 (starts once down): a real bent-knee/bent-elbow kick,
            // each downstream part repositioned to its measured joint after
            // its upstream part rotates — this is what was missing before;
            // rotation alone always left the downstream part sitting still.
            if (p2 >= 1)
            {
               if (this.tears.length == 0) this.createTears();
               this.updateTears();

               var kick:Number = t * 0.5;

               var thighF:Number = Math.sin(kick) * 35;
               this.rig.frontthigh.rotation = thighF;
               this.repositionAtJoint(this.rig.frontthigh, this.rig.frontshin, this.kneeOffsetFront);
               this.rig.frontshin.rotation = thighF + Math.sin(kick * 1.4) * 20;
               this.repositionAtJoint(this.rig.frontshin, this.rig.idlefoot, this.ankleOffsetFront);
               this.rig.idlefoot.rotation = this.rig.frontshin.rotation;

               var thighB:Number = Math.sin(kick + Math.PI) * 35;
               this.rig.backthigh.rotation = thighB;
               this.repositionAtJoint(this.rig.backthigh, this.rig.backshin, this.kneeOffsetBack);
               this.rig.backshin.rotation = thighB + Math.sin(kick * 1.4 + Math.PI) * 20;
               this.repositionAtJoint(this.rig.backshin, this.rig.backfoot, this.ankleOffsetBack);
               this.rig.backfoot.rotation = this.rig.backshin.rotation;

               var armF:Number = Math.sin(kick + 1.0) * 40;
               this.rig.frontshoulder.rotation = armF;
               this.repositionAtJoint(this.rig.frontshoulder, this.rig.fronthand, this.handOffsetFront);
               this.rig.fronthand.rotation = armF;

               var armB:Number = Math.sin(kick + 1.0 + Math.PI) * 40;
               this.rig.backshoulder.rotation = armB;
               this.repositionAtJoint(this.rig.backshoulder, this.rig.backhand, this.handOffsetBack);
               this.rig.backhand.rotation = armB;

               this.rig.head.rotation = 25 + Math.sin(t * 0.5) * 5;
            }

            // Darken/desaturate over time, independent of the pose.
            var p3:Number = Math.min(t / 50, 1);
            var e3:Number = 1 - Math.pow(1 - p3, 3);
            var dim:Number = 1 - e3 * 0.5;
            this.rig.transform.colorTransform = new ColorTransform(dim, dim, dim, 1, 0, 0, 0, 0);
         }
      }

      private function ioErrorHandler(event:IOErrorEvent) : void
      {
         trace("ioErrorHandler: " + event);
      }
   }
}
