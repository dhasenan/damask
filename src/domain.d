module dmud.domain;

import std.uni, std.string;

// TODO in-mud calendar; day / night cycle; seasons
// TODO concrete conversion to real-world time
struct Time {
	static Time zero = {0};
	long ticks;

	bool opEquals(Time other) {
		return ticks == other.ticks;
	}

	int opCmp(Time other) {
		return ticks == other.ticks ? 0 :
			ticks < other.ticks ? -1 : 1;
	}

	Time opBinary(string s)(Span other) if (s == "+") {
		return Time(ticks + other.ticks);
	}

	Time opBinary(string s)(Span other) if (s == "-") {
		return Time(ticks - other.ticks);
	}

	Time opBinary(string s)(Time other) if (s == "-") {
		return Span(ticks - other.ticks);
	}
}

struct Span {
	long ticks;
}

class MudObj {
	/// Internal ID. This should be a human-readable string.
	/// Recommended format should be path-style, eg "/core/mobs/farmers/turnip_farmer".
	string id;

	/// Autogenerated ID number.
	int idNum;

	/// User-visible name for the object. What they see when they look at it.
	/// Example: "The Reverend", "bodging knife", "The Inn at the Market"
	string name;

	/// What the player sees when looking at this thing.
	string description;

	/// Other names by which this object can be referred to.
	string[] aliases;

	/// The current command generation of this mud object.
	/// For objects that can act (players, mobs, scripted items), this is the cancellation mechanism
	/// for scheduled actions.
	int generation;

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
}

class Item : MudObj {
	/// An item is always in something else. A room, a mob's inventory, or a
	/// container. This is what it's in.
	MudObj containing;
}

class Room : MudObj {
	Mob[] mobs;
	Item[] items;
}

abstract class Command {
	private int _generation;
	final void act(MudObj self) {
		if (self.generation != _generation) {
			return;
		}
		doAct(self);
	}

	abstract void doAct(MudObj self);
}

interface IBehavior {
	Command next(Time now);
}

// TODO: some sort of MobRecipe so I can have variants.
// Some simple text replacement in the description and name, some attribute variation, etc.
class Mob : MudObj {
	Room location;
	Item[] inventory;
	ISink sink = new Sink();
}

interface ISink {
	void write(string value);
}

class Sink : ISink {
	void write(string value) {}
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
class Zone : MudObj {
	/// Rooms belonging to this zone.
	Room[] rooms;

	/// The mobs that randomly spawn in this zone.
	// TODO: what about mob groups? Like a banker and a bodyguard?
	Mob[] mobs;
}


class World {
	Mob[string] mobs;
	Zone[string] zones;
	Item[string] items;
}
