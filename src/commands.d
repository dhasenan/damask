module dmud.commands;

import dmud.domain;

class Look : Command {
	string target;
	override void doAct(MudObj self) {
		auto mob = cast(Mob)self;
		if (!mob) {
			// Zones, rooms, items, etc can't look at things.
			return;
		}
		// We need to locate the mudobj in question.
		// It might be in the player's inventory or in the room.
		foreach (item; mob.inventory) {
			if (item.identifiedBy(target)) {
				// TODO how do I write this out to the mob?
				return;
			}
		}
	}
}