module dmud.citygen;

import std.algorithm;
import std.exception;
import std.format;
import std.math;
import std.random;
import std.stdio;

import dmud.component;
import dmud.domain;
import dmud.util;

@safe:

class GenInfo : Component {
	this() { canSave = false; }
	// The type of thing that was generated.
	// For instance, 'wall' or 'tower'.
	string typeHint;
}


class CityGen {
	ComponentManager cm;
	Mt19937 rnd;
	int radius;
	int rVariance;
	Cube!Entity rooms;
	Entity zoneEntity;

	this() {
		cm = ComponentManager.instance;
		rnd = Mt19937(112);
		radius = uniform(60, 100, rnd);
		rVariance = radius / 10;
		rooms = Cube!Entity(radius + rVariance);
		zoneEntity = cm.next;
		zoneEntity.add!Zone;
	}

	Entity makeCity(bool assignStartRoom = true) {
		// Pick towers for each Kdrant.
		Point[] towers;
		auto segments = uniform!"[]"(4, 8, rnd);
		auto region = PI * 2 / segments;
		for (int i = 0; i < segments; i++) {
			auto start = region * i;
			auto end = region * (i + 1);
			auto angle = uniform!"[]"(start, end, rnd);
			auto dist = uniform!"[]"(radius - rVariance, radius + rVariance, rnd);
			auto tower = toCoords(angle, dist);
			towers ~= tower;
		}

		// Pick a few additional towers.
		auto extraTowers = uniform!"[]"(2, 3, rnd);
		for (int i = 0; i < extraTowers; i++) {
			auto angle = uniform!"[]"(0, PI * 2, rnd);
			auto dist = uniform!"[]"(radius - rVariance, radius + rVariance, rnd);
			towers ~= toCoords(angle, dist);
		}
		towers.sort!((a, b) => atan2(cast(real)a.x, cast(real)a.y) < atan2(cast(real)b.x, cast(real)b.y));

		// TODO: prune towers producing bad angles

		// Add towers to the map.
		foreach (i, tower; towers) {
			Room last;
			for (long height = 0; height < tower.z; height++) {
				auto e = cm.next;
				auto r = e.add!Room;
				r.zone = zoneEntity;
				auto room = e.add!MudObj;
				auto gi = e.add!GenInfo;
				gi.typeHint = "tower";
				room.name = "The staircase of Tower %s (height %s)".format(i + 1, height);
				room.description = "You are in a mighty tower named %s.".format(i + 1);
				r.localPosition = Point(tower.x, tower.y, height);
				rooms[tower] = e;
				if (last !is null) {
					last.dig(r, true);
				}
				last = r;
			}
			{
				auto e = cm.next;
				auto r = e.add!Room;
				r.zone = zoneEntity;
				auto room = e.add!MudObj;
				room.name = "The top of Tower %s".format(i + 1);
				room.description = "You are at the top of a mighty tower named %s.".format(i + 1);
				r.localPosition = tower;
				auto gi = e.add!GenInfo;
				gi.typeHint = "tower";
				rooms[tower] = e;
				if (last !is null) {
					last.dig(r, true);
				}
			}
		}

		// Add walls.
		foreach (i, tower; towers) {
			auto targetIndex = (i + 1) % towers.length;
			auto target = towers[targetIndex];
			drawLine(tower, target, (obj) {
					obj.name = "City Wall %s".format(obj.entity.value);
					obj.description = "A section of city wall between Tower %s and Tower %s".format(i + 1, targetIndex + 1);
					auto gi = obj.entity.add!GenInfo;
					gi.typeHint = "wall";
					});
		}

		// Now we want to create roads.
		// We start with the center point (it's guaranteed to be within the walls.)
		// Then we perturb it a bit, randomly, staying within the walls.
		auto numRoads = uniform!"[]"(4, 7, rnd);
		for (int i = 0; i < numRoads; i++) {
			auto idx = uniform(0, towers.length, rnd);
			auto t1 = towers[idx];
			auto t2 = towers[(idx + 1) % towers.length];
			auto wall = Line(t1, t2);
			auto p = wall.randomPoint(rnd);
			// grab a random point in the wall
		}

		if (assignStartRoom) {
			auto w = world.get!World;
			w.startingRoom = rooms.nonDefaults.filter!(x => x != Invalid).front;
		}

		auto f = File("/home/dhasenan/foo.svg", "w");
		f.writef(`<svg width="%s" height="%s" xmlns="http://www.w3.org/2000/svg">
				<path d="M `, radius * 2 + 10, radius * 2 + 10);
		auto off = radius + 2;
		foreach (i, tower; towers) {
			if (i > 0) {
				f.writef(" L ");
			}
			assert(tower.x + off > 0, tower.toString);
			assert(tower.y + off > 0, tower.toString);
			f.writef("%s %s", tower.x + off, tower.y + off);
		}
		f.writeln(` Z" fill="#eeeeaa" stroke="#dedede"/>`);
		foreach (e; rooms.nonDefaults) {
			if (e == Invalid) continue;
			auto room = e.get!Room;
			foreach (exit; room.exits) {
				auto src = room.localPosition;
				auto dest = exit.target.get!(Room).localPosition;
				f.writefln(`<line x1="%s" y1="%s" x2="%s" y2="%s" stroke="black" stroke-width="0.2" />`,
						src.x + off, src.y + off, dest.x + off, dest.y + off);
			}
		}
		foreach (e; rooms.nonDefaults) {
			auto room = e.get!Room;
			if (room is null) continue;
			auto p = room.localPosition;
			string color = "red";
			auto gi = e.get!GenInfo;
			if (gi) {
				switch (gi.typeHint) {
					case "tower":
						color = "black";
						break;
					case "wall":
						color = "#aaaaaa";
						break;
					case "street":
						color = "#fe2274";
						break;
					default:
						break;
				}
			}
			assert(p.x + off > 0, p.toString);
			assert(p.y + off > 0, p.toString);
			f.writefln(`	<circle cx="%s" cy="%s" r="0.4" fill="%s" stroke="black" stroke-width="0.1"/>`, p.x + off, p.y + off, color);
		}
		f.writeln(`</svg>`);

		return zoneEntity;
	}

	void drawLine(Point source, Point target, void delegate(MudObj) @safe roomModifier)
		in {
			enforce(source.z == target.z, "can only draw horizontal lines");
		} body {
			auto dist = source.dist(target);
			auto dx = abs(target.x - source.x);
			auto dy = abs(target.y - source.y);

			auto ordinals = min(dx, dy);
			auto cardinals = max(dx, dy) - ordinals;

			// Determine the major and minor directions.
			// Careful about division by zero.
			Point majorDirection, minorDirection;
			majorDirection.x = (target.x - source.x) / (dx == 0 ? 1 : dx);
			majorDirection.y = (target.y - source.y) / (dy == 0 ? 1 : dy);
			if (dx > dy) {
				minorDirection.x = majorDirection.x;
			} else {
				minorDirection.y = majorDirection.y;
			}
			if (ordinals < cardinals) {
				auto tmp = majorDirection;
				majorDirection = minorDirection;
				minorDirection = tmp;
			}

			// We will travel the total distance between source and target by rotating between
			// rooms with offset majorDirection and minorDirection.
			// We can't maintain a precise rotation -- for instance, if we need to travel 25
			// rooms on the X axis and 19 rooms on the Y axis, we have 6 cardinal and 19 ordinal
			// rooms to travel. We can't make that precisely even.
			// Instead, we will place rooms in the major direction, and each room in the major
			// direction earns credits toward a room in the minor direction. When we have one
			// full credit in the minor direction, we place that instead.

			auto left = min(source.x, target.x);
			auto right = max(source.x, target.x);
			auto down = min(source.y, target.y);
			auto up = max(source.y, target.y);

			double creditsPerRoom = (1.0 * min(ordinals, cardinals)) / max(ordinals, cardinals);
			double credits = 0;
			Point p = source;
			while (p != target) {
				auto last = p;
				// Floating point inaccuracies.
				// This should be good enough, as long as we don't generate really huge cities.
				if (credits >= 0.9999) {
					credits -= 1;
					p += minorDirection;
				} else {
					p += majorDirection;
					credits += creditsPerRoom;
				}
				assert(!(p.x < left || p.x > right || p.y < down || p.y > up),
						"traveled out of bounds! from point: %s to: %s reached: %s\nbounds: %s %s %s %s".format(
							source, target, p, left, right, up, down));
				Room room;
				if (rooms[p] == None) {
					auto e = cm.next;
					room = e.add!Room;
					room.zone = zoneEntity;
					room.localPosition = p;
					auto obj = e.add!MudObj;
					if (roomModifier) roomModifier(obj);
					rooms[p] = e;
				} else {
					room = rooms[p].get!Room;
				}

				auto v = rooms[last].get!Room;
				if (!room.dig(v, true)) {
					throw new Exception("failed to dig from %s to %s".format(room.localPosition, v.localPosition));
				}

				// The wall logically extends from the ground up.
				// While later things should be able to overwrite it, it shouldn't be the default.
				auto lookOutBelow = p;
				lookOutBelow.z = 0;
				rooms[lookOutBelow] = Invalid;
			}
		}


}

enum WALL_HEIGHT = 3;

struct Line {
	Point a, b;
	bool intersect(Line other) {
		if (left > other.right || right < other.left || top < other.bottom || bottom > other.top) {
			// bounding boxes don't overlap
			return false;
		}
		if (a.x == b.x || a.y == b.y) {
			// The bounding boxes overlap.
			// A vertical line has a trivial bounding box.
			// Therefore they intersect.
			return true;
		}
		if (other.a.x == other.b.x || other.a.y == other.b.y) {
			return true;
		}
		auto angleA = angle3(b, a, other.a);
		auto angleB = angle3(b, a, other.b);
		// One point is right of this line; the other is left of it.
		if ((angleA <= PI) != (angleB <= PI)) {
			return true;
		}
		return false;
	}

	Point randomPoint(TRand)(ref TRand rnd) {
		return a + (b - a) * uniform(0, length, rnd);
	}

	double length() { return a.dist(b); }

	long roomLength() {
		auto dx = abs(a.x - b.x);
		auto dy = abs(a.y - b.y);
		return max(dx, dy);
	}

	long left() { return min(a.x, b.x); }
	long right() { return max(a.x, b.x); }
	long top() { return min(a.y, b.y); }
	long bottom() { return max(a.y, b.y); }
}


unittest {
	import std.conv;
	auto p = toCoords(0, 100);
	assert(p.x == 100, p.toString);
	assert(p.y == 0);

	p = toCoords(PI/2, 100);
	assert(p.x == 0, p.toString);
	assert(p.y == -100, p.toString);

	p = toCoords(PI, 100);
	assert(p.x == -100, p.toString);
	assert(p.y == 0, p.toString);

	p = toCoords(PI * 1.5, 100);
	assert(p.x == 0, p.toString);
	assert(p.y == 100, p.toString);

	p = toCoords(PI * 0.25, 100);
	assert(p.x == 71, p.toString);
	assert(p.y == -71, p.toString);
}

double angleOf(Point p) {
	auto a = atan2(cast(real)p.x, cast(real)p.y);
	if (a < 0) {
		a += PI;
	}
	return a;
}

double angle3(Point a, Point vertex, Point b) {
	auto a1 = a - vertex;
	auto b1 = b - vertex;
	return angleOf(a) - angleOf(b);
}

unittest {
	assert(
			approxEqual(angle3(
				Point(4, 0, 0),
				Point(0, 0, 0),
				Point(0, 5, 0)),
			PI * 1.5, 0.01));
	assert(
			approxEqual(angle3(
				Point(4, 0, 0),
				Point(1, 0, 0),
				Point(1, 5, 0)),
			PI * 1.5, 0.01));
}

Point toCoords(double angle, double length) {
	Point p;
	p.z = WALL_HEIGHT;
	p.x = abs(lrint(cos(angle) * length));
	p.y = abs(lrint(sin(angle) * length));
	if (angle > PI * 0.5 && angle <= 1.5 * PI) {
		// left half
		p.x = -p.x;
	}
	if (angle > 0 && angle <= PI) {
		// bottom half
		p.y = -p.y;
	}
	return p;
}
