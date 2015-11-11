module dmud.domain;

import std.algorithm;
import std.datetime;
import std.range;
import std.string;
import std.uni;

import dmud.component;
import dmud.log;
import dmud.telnet_socket;

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
		logger.info("[{}] != [{}]", name, str);
		foreach (a; aliases) {
			if (a.toLower == str.toLower) {
				return true;
			}
			logger.info("[{}] != [{}]", a, str);
		}
		return false;
	}
}

class Room : Component {
	Entity[] mobs;
	Entity[] items;
	Exit[] exits;

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
class Zone {
	/// Rooms belonging to this zone.
	Room[] rooms;

	/// The mobs that randomly spawn in this zone.
	// TODO: what about mob groups? Like a banker and a bodyguard?
	Mob[] mobs;
}


class Inventory : Component {
	Entity[] items;
	int opApply(int delegate(Entity) dg) {
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
	}
}


class AllNews : Component {
	NewsItem[] news;
}


class PlayerNewsStatus : Component {
	string lastRead;
}


Entity world;
static this() {
	world = ComponentManager.instance.next;
}

class World : Component {
	Entity startingRoom;
	string name;
	string banner;
}
