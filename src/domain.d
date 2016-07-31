module dmud.domain;

import std.algorithm;
import std.datetime;
import std.experimental.logger;
import std.range;
import std.string;
import std.uni;
import experimental.units;
import experimental.units.si;

import dmud.component;
import dmud.telnet_socket;
import dmud.util;

@safe:

class MudObj : Component {
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

class Item : MudObj {
	/// An item is always in something else. A room, a mob's inventory, or a
	/// container. This is what it's in.
	MudObj containing;
}

struct Exit {
	Entity target;
	string name;
	string[] aliases;
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
	Entity[] mobs;
	Entity[] items;
	Entity zone;
	Exit[] exits;
	/// The position of the room within its zone.
	Point localPosition;

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
		if (!p.adjacent(q)) {
			writefln("tried to dig from non-adjacent %s to %s", p, q);
			return false;
		}
		Exit exit;
		// TODO vertical
		if (p.y < q.y) {
			// other is south of us
			if (p.x < q.x) {
				// other is west of us
				exit.name = "southwest";
				exit.aliases = ["sw"];
			} else if (p.x > q.x) {
				exit.name = "southeast";
				exit.aliases = ["se"];
			} else {
				exit.name = "south";
				exit.aliases = ["s"];
			}
		} else if (p.y > q.y) {
			if (p.x < q.x) {
				exit.name = "northwest";
				exit.aliases = ["nw"];
			} else if (p.x > q.x) {
				exit.name = "northeast";
				exit.aliases = ["ne"];
			} else {
				exit.name = "north";
				exit.aliases = ["n"];
			}
		} else {
			if (p.x < q.x) {
				exit.name = "west";
				exit.aliases = ["w"];
			} else if (p.x > q.x) {
				exit.name = "east";
				exit.aliases = ["e"];
			} else {
				writefln("no case to handle %s -> %s", p, q);
				return false;
			}
		}
		exit.target = other.entity;
		exits ~= exit;
		if (includeReverse) {
			return other.dig(this, false);
		}
		return true;
	}
}

class Behavior {

}

// TODO: some sort of MobRecipe so I can have variants.
// Some simple text replacement in the description and name, some attribute variation, etc.
class Mob : MudObj {
	Room room;
	Item[] inventory;
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
	/// The mobs that randomly spawn in this zone.
	// TODO: what about mob groups? Like a banker and a bodyguard?
	Mob[] mobs;

	/++
		+ How large a room is, if not otherwise specified.
		+/
	Quantity!Metre defaultRoomScale;

	this() {
		defaultRoomScale = 10 * metre;
	}
}


class Inventory : Component {
	Entity[] items;
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
	string id;
	string news;
	SysTime date;

	this(SysTime date, string news) {
		this.date = date;
		this.news = news;
		this.id = date.toSimpleString();
	}
}


class AllNews : Component {
	NewsItem[] news;
}


class PlayerNewsStatus : Component {
	string lastRead;
}


// The world is always entity 1.
Entity world = cast(Entity)1;

class World : Component {
	Entity startingRoom;
	string name;
	string banner;
}
