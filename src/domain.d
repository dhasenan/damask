module dmud.domain;

import std.algorithm;
import std.datetime;
import std.experimental.logger;
import std.range;
import std.string;
import std.uni;
import experimental.units;
import experimental.units.si;
import jsonizer;

import dmud.component;
import dmud.telnet_socket;
import dmud.util;

@safe:

class MudObj : Component {
	mixin JsonSupport;

	@jsonize {
		/// User-visible name for the object. What they see when they look at it.
		/// Example: "The Reverend", "bodging knife", "The Inn at the Market"
		string name;

		/// What the player sees when looking at this thing.
		string description;

		/// Other names by which this object can be referred to.
		string[] aliases;

		/// What this thing is in.
		/// If this is an item, the container or room it's in.
		/// Player: room.
		/// Room: zone.
		/// Zone: world.
		Entity containing;
	}

	override string toString() { return name; }

	string the() {
		if (isUpper(name[0])) {
			return name;
		}
		if (name.startsWith("the")) {
			return name;
		}
		return "the " ~ name;
	}

	string a() {
		if (isUpper(name[0])) {
			return name;
		}
		if (name.startsWith("the")) {
			return name;
		}
		return "a " ~ name;
	}

	bool identifiedBy(string phrase) {
		if (name == phrase) return true;
		foreach (n; aliases) {
			if (n == phrase) return true;
		}
		return false;
	}

	string lookAt(Entity mob) {
		return description;
	}
}

struct Exit {
	mixin JsonSupport;
	@jsonize {
		Entity target;
		string name;
		string[] aliases;
	}

	bool identifiedBy(string str) {
		if (name.toLower == str.toLower) {
			return true;
		}
		sharedLog.infof("[%s] != [%s]", name, str);
		foreach (a; aliases) {
			if (a.toLower == str.toLower) {
				return true;
			}
			sharedLog.infof("[%s] != [%s]", a, str);
		}
		return false;
	}
}

class Room : Component {
	mixin JsonSupport;
	@jsonize {
		Entity[] mobs;
		Entity[] items;
		Entity zone;
		Exit[] exits;
		/// The position of the room within its zone.
		Point localPosition;
	}

	string lookAt(Entity mob) {
		// TODO visibility (which items can I see? which mobs? are any exits hidden?)
		auto s = entity.get!MudObj;
		with (s)
			return name ~ '\n' ~
				description ~ '\n' ~
				line("Exits", exits) ~
				line("Mobs", mobs.filter!(x => x !is mob).map!(x => x.get!MudObj)) ~
				line("Items", items.map!(x => x.get!MudObj));
	}

	// TODO: color
	// TODO: omit player from mob list
	string line(T)(string id, T items) {
		if (items.empty) return "";
		return id ~ ": " ~ items.map!(x => x.name).join(", ") ~ '\n';
	}

	private {
		struct Em {
			string full;
			string fragment;
		}
		static Em[Point] dirs;
		static this() {
			dirs =
			[
				Point(1, 1, 0): Em("southwest", "sw"),
				Point(-1, 1, 0): Em("southeast", "se"),
				Point(1, -1, 0): Em("northwest", "nw"),
				Point(-1, -1, 0): Em("northeast", "ne"),
				Point(1, 0, 0): Em("west", "w"),
				Point(-1, 0, 0): Em("east", "e"),
				Point(0, 1, 0): Em("south", "s"),
				Point(0, -1, 0): Em("north", "n"),
				Point(0, 0, -1): Em("up", "u"),
				Point(0, 0, 1): Em("down", "d"),
			];
		}
	}

	bool dig(Room other, bool includeReverse) {
		import std.stdio;
		foreach (exit; exits) {
			if (exit.target == other.entity) {
				if (includeReverse) {
					return other.dig(this, false);
				}
				return true;
			}
		}
		if (other.zone != this.zone) {
			writefln("tried to mix zones %s and %s", zone, other.zone);
			return false;
		}
		auto p = localPosition;
		auto q = other.localPosition;
		auto d = p - q;
		auto em = d in dirs;
		if (em is null) {
			writefln("tried to dig from non-adjacent %s to %s", p, q);
			return false;
		}
		Exit exit;
		exit.name = em.full;
		exit.aliases = [em.fragment];
		exit.target = other.entity;
		exits ~= exit;
		if (includeReverse) {
			return other.dig(this, false);
		}
		return true;
	}

	unittest {
		auto r1 = new Room;
		r1.localPosition = Point(2, 3, 0);
		auto r2 = new Room;
		r2.localPosition = Point(2, 3, 1);
		r1.dig(r2, true);

		assert(r1.exits.length == 1);
		assert(r2.exits.length == 1);
		assert(r1.exits[0].name == "up");
		assert(r2.exits[0].name == "down");
	}
}

class Behavior {

}

// TODO: some sort of MobRecipe so I can have variants.
// Some simple text replacement in the description and name, some attribute variation, etc.
class Mob : MudObj {
	mixin JsonSupport;
	Behavior behavior;

	void write(string value) {}

	void writeln(string value) {}
}

/* TODO what kind of separation do I want between the base definition of the world and its
 * current state?
 *
 * I could have the base def essentially be a serialized version of a state -- that makes it pretty
 * easy to start up but means little flexibility.
 *
 * I could have template versions of everything. In order to load a world, I instantiate a series of
 * RoomTemplates, each of which involves instantiating MobTemplates and so on.
 *
 * I could have rooms be fixed. Some specify which mobs should be in them; some are parts of zones
 * that specify what types of mobs can spawn there at random. Then, on load and randomly after that,
 * we spawn more mobs. Ensure that there's at least X mobs per room and no more than Y, sort of
 * thing, in a given zone.
 */


/** A zone is a group of rooms with similar treatment.
 * For now, "similar treatment" pretty much means mob spawns.
 */
class Zone : Component {
	mixin JsonSupport;
	@jsonize {
		/// The mobs that randomly spawn in this zone.
		// TODO: what about mob groups? Like a banker and a bodyguard?
		Mob[] mobs;

		// Provided for json conversion.
		@system {
		double roomScale() { return defaultRoomScale.toValue; }
		void roomScale(double value) { defaultRoomScale = value * metre; }

		}
	}

	/++
		+ How large a room is, if not otherwise specified.
		+/
		Quantity!Metre defaultRoomScale;

	this() {
		defaultRoomScale = 10 * metre;
	}
}


class Inventory : Component {
	mixin JsonSupport;
	@jsonize {
		Entity[] items;
	}

	int opApply(int delegate(Entity) @safe dg) {
		int result = 0;
		foreach (i; items) {
			result = dg(i);
			if (result) break;
		}
		return result;
	}
}


class NewsItem {
	mixin JsonSupport;
	@jsonize {
		string id;
		string news;
		SysTime date;
	}

	this(SysTime date, string news) {
		this.date = date;
		this.news = news;
		this.id = date.toSimpleString();
	}
}


class AllNews : Component {
	mixin JsonSupport;
	@jsonize {
		NewsItem[] news;
	}
}


class PlayerNewsStatus : Component {
	mixin JsonSupport;
	@jsonize {
		string lastRead;
	}
}


// The world is always entity 1.
Entity world = Entity(1);

class World : Component {
	mixin JsonSupport;
	@jsonize {
		Entity startingRoom;
		string name;
		string banner;
	}
}
