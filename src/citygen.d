// vim: set ts=2 sw=2 noexpandtab
module dmud.citygen;

import std.algorithm;
import std.array;
import std.container.dlist;
import std.conv;
import std.exception;
import std.experimental.logger;
import std.format;
import std.math;
import std.random;
import std.range;
import std.stdio;

import dosimplex.generator;

import dmud.component;
import dmud.domain;
import dmud.util;

@safe:

/**
  * A feature is something that can appear in a room.
  * It'll be converted to a doodad eventually.
  */
struct Feature {
  string name;
  string[] aliases;
  string[] adjectives;
  string[] descriptions;
}

Feature[] islandFeatures() {
  return [
    Feature("sycamore tree", ["sycamore", "tree"], ["tall", "broad-leafed"], ["a tall sycamore with broad leaves"]),
    Feature("spruce sapling", ["spruce", "sapling"], ["scruffy-looking", "scruffy"], ["a tiny spruce sapling in a heap of fallen needles"])
  ];
}

class GenInfo : Component {
	this() { canSave = false; }
	// The type of thing that was generated.
	// For instance, 'wall' or 'tower'.
	string typeHint;
}

enum cardinalDirections = [
	Point(1, 0, 0),
	Point(-1, 0, 0),
	Point(0, 1, 0),
	Point(0, -1, 0)
];

enum flatDirections = [
	Point(1, 0, 0),
	Point(-1, 0, 0),
	Point(0, 1, 0),
	Point(0, -1, 0),
	Point(1, 1, 0),
	Point(1, -1, 0),
	Point(-1, 1, 0),
	Point(-1, -1, 0)
];


T orDefault(T, U)(T[U] aa, U val) {
	if (auto p = val in aa) {
		return *p;
	}
	return T.init;
}

abstract class Gen {
	ComponentManager cm;
	Mt19937 rnd;
	int radius;
	int rVariance;
	Cube!Entity rooms;
	Entity zoneEntity;

	this(int minRadius, int maxRadius, int variance) {
		cm = ComponentManager.instance;
		rnd = Mt19937(unpredictableSeed);
		radius = uniform(minRadius, maxRadius, rnd);
		rVariance = variance;
		rooms = Cube!Entity(radius + rVariance);
		zoneEntity = cm.next;
		zoneEntity.add!Zone;
	}

  abstract Entity generate(bool assignStartRoom = false);

	int limit() @property { return radius + rVariance; }

  void writeToFile(string filename, string[string] colors) {
    enum scale = 20;
    enum stroke = 0.1 * scale;
    enum exitwidth = 0.2 * scale;
    enum rad = 0.4 * scale;
    long minX, minY, maxX, maxY;
    foreach (e; rooms.nonDefaults) {
      auto p = e.get!(Room).localPosition;
      if (minX > p.x) {
        minX = p.x;
      }
      if (minY > p.y) {
        minY = p.y;
      }
      if (maxX < p.x) {
        maxX = p.x;
      }
      if (maxY < p.y) {
        maxY = p.y;
      }
    }
		auto f = File(filename, "w");
		f.writef(`<svg width="%s" height="%s" xmlns="http://www.w3.org/2000/svg">
`,
        (maxX - minX + 10) * scale,
        (maxY - minY + 10) * scale);
		auto offX = -minX + 5;
		auto offY = -minY + 5;
    auto off = Point(offX, offY, 0) * scale;
    f.writef(`<!-- off: %s scale: %s -->
`, off, scale);
		foreach (e; rooms.nonDefaults) {
			if (e == Invalid) continue;
			auto room = e.get!Room;
			foreach (exit; room.exits) {
				auto src = room.localPosition * scale + off;
				auto dest = exit.target.get!(Room).localPosition * scale + off;
				f.writefln(`<line x1="%s" y1="%s" x2="%s" y2="%s" stroke="black" stroke-width="%s" />`,
						src.x, src.y, dest.x, dest.y, exitwidth);
			}
		}
		foreach (e; rooms.nonDefaults) {
			auto room = e.get!Room;
			if (room is null) continue;
			auto p = (room.localPosition * scale) + off;
			string color = "red";
			auto gi = e.get!GenInfo;
			if (gi) {
        auto cp = gi.typeHint in colors;
        if (cp) color = *cp;
			}
			assert(p.x > 0 && p.y > 0, "tried to draw out of bounds: %s".format(p));
			f.writefln(`<!-- %s -->`, room.localPosition);
			f.writefln(`	<circle cx="%s" cy="%s" r="%s" fill="%s" stroke="black" stroke-width="%s"/>`,
          p.x, p.y, rad, color, stroke);
		}
		f.writeln(`</svg>`);
  }
}

class IslandGenInfo : Component {
	this() { canSave = false; }
  double fecundity = 1;
  bool isWater = false;
}

class IslandGen : Gen {
  enum droprate = 0.2;
  enum dropvar = 0.2;
  this() {
    super(60, 100, 8);
  }

  Entity generate(bool assignStartRoom = false) {
    // Start out with a handful of rooms in the center half.
    DList!Point queue;
    int roomcount = 0;
    auto nexuses = uniform(3, 5, rnd);
    auto waters = uniform(2, nexuses + 1, rnd);
    Point[] waterSources;
    foreach (i; 0..nexuses) {
      auto p = randomPointInCircle(rnd, radius / 2.3);
      if (i < waters) waterSources ~= p;
      auto r = makeRoom(p, 1 + uniform(-5.0, 5.0, rnd) / 20);
      queue ~= p;
      if (assignStartRoom) {
        auto w = world.get!World;
        w.startingRoom = r;
      }
      roomcount++;
    }

    while (!queue.empty) {
      auto p = queue.front;
      queue.removeFront;
      auto e = rooms[p];
      auto igi = e.get!IslandGenInfo;
      auto sroom = e.get!Room;
      foreach (x; -1..2) {
        foreach (y; -1..2) {
          auto p2 = p + Point(x, y, 0);
          if (!rooms.inBounds(p2)) {
            // No, *you* are out of line!
            continue;
          }
          if (rooms.contains(p2)) {
            // Don't overwrite.
            continue;
          }
          auto fecundity = igi.fecundity - (droprate - uniform(-dropvar, dropvar, rnd));
          if (fecundity <= 0) {
            // I don't have the strength to go on.
            continue;
          }
          auto e2 = makeRoom(p2, fecundity);
          queue ~= p2;
          roomcount++;
          if (uniform(0, 512) == 0) {
            waterSources ~= p2;
          }
        }
      }
    }

    // Now do water!
    foreach (w; waterSources) {
      queue ~= w;
    }
    while (!queue.empty) {
      auto p = queue.front;
      queue.removeFront;
      auto e = rooms[p];
      auto igi = e.get!(IslandGenInfo);
      igi.isWater = true;
      e.get!(GenInfo).typeHint = "water";
      // Pick a random neighbor with lower fecundity.
      // If one's already water, be a tributary.
      Entity[] neighbors;
      bool isTributary = false;
      foreach (x; -1..2) {
        foreach (y; -1..2) {
          if (x == 0 && y == 0) {
            continue;
          }
          auto p2 = Point(p.x + x, p.y + y, 0);
          if (rooms.inBounds(p2) && rooms.contains(p2)) {
            auto e2 = rooms[p2];
            auto igi2 = e2.get!IslandGenInfo;
            // water only flows downhill
            if (igi2.fecundity <= igi.fecundity) {
              if (igi2.isWater) {
                isTributary = true;
                break;
              }
              neighbors ~= rooms[p2];
            }
          }
        }
      }
      if (isTributary) {
        continue;
      }
      if (neighbors.length == 0) {
        continue;
      }

      // Pick a random neighbor and fall in!
      queue ~= waterRandomChild(neighbors).get!(Room).localPosition;
    }

    // Finally, link rooms together.
    foreach (e; rooms.nonDefaults) {
      auto r = e.get!Room;
      foreach (p; r.localPosition.neighbors) {
        auto e2 = rooms[p];
        if (e2 == None) continue;
        r.dig(e2.get!Room, true);
      }
    }

    infof("created %s rooms for %s", roomcount, zoneEntity);
    writeToFile(
        "island%s.svg".format(zoneEntity.value),
        ["sky-island": "#1C6C2A", "water": "#71AFD0"]);
    return zoneEntity;
  }

  private Entity waterRandomChild(ref Entity[] generated) {
    auto child = uniform(0, generated.length, rnd);
    auto toWater = generated[child];
    generated[child] = generated[$-1];
    generated.length--;
    toWater.get!(IslandGenInfo).isWater = true;
    toWater.get!(GenInfo).typeHint = "water";
    return toWater;
  }

  private Entity makeRoom(Point p, double fecundity) {
    auto entity = cm.next;
    rooms[p] = entity;
    auto room = entity.add!Room;
    room.zone = zoneEntity;
    room.localPosition = p;
    // TODO room description
    auto mo = entity.add!MudObj;
    mo.name = "Sky island wilderness";
    mo.description = "A random spot in the wilderness on a sky island.";
    mo.containing = zoneEntity;
    auto genInfo = entity.add!IslandGenInfo;
    genInfo.fecundity = fecundity;
    auto gi = entity.add!GenInfo;
    gi.typeHint = "sky-island";
    return entity;
  }
}

class CityGen : Gen {
	Point[] towers;
	Wall[] walls;

	this() {
    super(60, 100, 8);
	}

  Entity generate(bool assignStartRoom = false) {
		// Pick towers for each Kdrant.
		auto segments = uniform!"[]"(4, 8, rnd);
		auto region = PI * 2 / segments;
		for (int i = 0; i < segments; i++) {
			auto start = region * i;
			auto end = region * (i + 1);
			auto angle = uniform!"[]"(start, end, rnd);
			auto dist = uniform!"[]"(radius - rVariance, radius + rVariance, rnd);
			auto tower = toCoords(angle, dist, WALL_HEIGHT);
			towers ~= tower;
		}

		// Pick a few additional towers.
		auto extraTowers = uniform!"[]"(2, 3, rnd);
		for (int i = 0; i < extraTowers; i++) {
			auto angle = uniform!"[]"(0, PI * 2, rnd);
			auto dist = uniform!"[]"(radius - rVariance, radius + rVariance, rnd);
			towers ~= toCoords(angle, dist, WALL_HEIGHT);
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
			Entity[] wallRooms = [];
			drawLine(tower, target, (obj) {
				obj.name = "City Wall %s".format(obj.entity.value);
				obj.description = "A section of city wall between Tower %s and Tower %s".format(i + 1, targetIndex + 1);
				auto gi = obj.entity.add!GenInfo;
				gi.typeHint = "wall";
				wallRooms ~= obj.entity;
			});
			walls ~= Wall(Line(tower, target), wallRooms);
		}

		auto noise = SNoiseGenerator(18842);
		// First, we draw the major roads...
		foreach (p; SimpleCityRoomRange(this)) {
			auto val = noise.noise2D(p.x, p.y);
			if (val >= -0.2) {
				continue;
			}
			auto e = cm.next;
			rooms[p] = e;
			auto room = e.add!Room;
			room.localPosition = p;
			room.zone = zoneEntity;
			auto mo = e.add!MudObj;
			auto gi = e.add!GenInfo;
			gi.typeHint = "street";
			mo.name = "A major street";
			mo.description = "A part of a major street";
			// try adding exits
			foreach (dir; flatDirections) {
				auto existing = rooms[p + dir];
				auto r2 = existing.get!Room;
				if (r2) {
					enforce(r2.dig(room, true),
							"failed to dig between side streets at %s and %s".format(
								room.localPosition, r2.localPosition));
				}
			}
		}

		// Insert a grid inside the remaining ground level spaces.
		foreach (yref; [-1, 1]) {
			for (int y = 0; y < radius + rVariance; y++) {
				if (rooms[Point(0, y * yref, WALL_HEIGHT)] != None) {
					// We hit the wall.
					break;
				}
				foreach (xref; [-1, 1]) {
					for (int x = 0; x < radius + rVariance; x++) {
						if (rooms[Point(x * xref, y * yref, WALL_HEIGHT)] != None) {
							// We hit the wall. Stop now.
							break;
						}
						if (y % 4 != 0) {
							if (x % 2 != 0) {
								continue;
							}
						}
						auto p = Point(x * xref, y * yref, 0);
						if (rooms[p] != None) {
							continue;
						}
						auto e = cm.next;
						rooms[p] = e;
						auto room = e.add!Room;
						room.localPosition = p;
						room.zone = zoneEntity;
						auto mo = e.add!MudObj;
						auto gi = e.add!GenInfo;
						gi.typeHint = "sideStreet";
						mo.name = "A side street";
						mo.description = "Just a side street";
						// try adding exits
						foreach (dir; [Point(0, 1, 0), Point(0, -1, 0), Point(1, 0, 0), Point(-1, 0, 0)]) {
							auto existing = rooms[p + dir];
							auto r2 = existing.get!Room;
							if (r2) {
								enforce(r2.dig(room, true),
										"failed to dig between side streets at %s and %s".format(
											room.localPosition, r2.localPosition));
							}
						}
					}
				}
			}
		}

		if (assignStartRoom) {
			auto w = world.get!World;
			w.startingRoom = rooms.nonDefaults.filter!(x => x != Invalid).front;
		}

    writeToFile("city%s.svg".format(zoneEntity.value), [
      "tower": "black",
      "wall": "#aaaaaa",
      "street": "#fe2274",
      "sideStreet": "#aafe74"
    ]);
    writefln("total of %s rooms generated", rooms.nonDefaults.walkLength);

		return zoneEntity;
	}

	/** Cheaply determines whether the point is in the city. */
	bool isInCityCheap(Point point) {
		foreach (dir; cardinalDirections) {
			auto p = Point(point.x, point.y, WALL_HEIGHT);
			bool found = false;
			while (isInBounds(p)) {
				if (rooms[p] != None) {
					found = true;
					break;
				}
				p += dir;
			}
			if (!found) {
				return false;
			}
		}
		return true;
		/+
		int crosses = 0;
		for (auto i = point.x; i <= rooms.radius; i++) {
			auto p = Point(i, point.y, 0);
			if (rooms[p] == Invalid) {
				infof("point %s right crosses invalid room at %s", point, p);
				crosses++;
			}
		}
		if (crosses % 2 == 0) return false;
		crosses = 0;
		for (auto i = point.x; i >= -rooms.radius; i--) {
			auto p = Point(i, point.y, 0);
			if (rooms[p] == Invalid) {
				infof("point %s left crosses invalid room at %s", point, p);
				crosses++;
			}
		}
		if (crosses % 2 == 0) return false;
		return true;
		+/
	}

	bool isInBounds(Point p) {
		return abs(p.x) <= limit &&
			abs(p.y) <= limit &&
			abs(p.z) <= limit;
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
			//infof("drawing line from %s to %s", source, target);
			int drawn = 0;
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
				if (rooms[p] == None || rooms[p] == Invalid) {
					drawn++;
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
				if (v !is null && !room.dig(v, true)) {
					throw new Exception("failed to dig from %s to %s".format(room.localPosition, v.localPosition));
				}

				// The wall logically extends from the ground up.
				// While later things should be able to overwrite it, it shouldn't be the default.
				auto lookOutBelow = p;
				lookOutBelow.z = 0;
				if (rooms[lookOutBelow] == None) {
					rooms[lookOutBelow] = Invalid;
				}
			}
		}
}

/**
	A range over rooms in the city.
 */
struct SimpleCityRoomRange {
	CityGen cg;
	int x, y;

	@disable this();

	this(CityGen cg) {
		this.cg = cg;
		this.x = -cg.limit + 1;
		this.y = -cg.limit + 1;
	}

	Point front() {
		return Point(x, y, 0);
	}

	bool empty() {
		return y >= cg.limit;
	}

	void popFront() {
		while (!empty) {
			x++;
			if (x > cg.limit) {
				x = -cg.limit + 1;
				y++;
			}
			if (y > cg.limit) {
				return;
			}
			if (cg.isInCityCheap(front)) {
				return;
			}
		}
	}
}

enum WALL_HEIGHT = 3;

struct Line {
	Point a, b;
	this(Point p1, Point p2) {
		if (p1.x < p2.x || (p1.x == p2.x && p1.y < p2.y)) {
			a = p1;
			b = p2;
		} else {
			a = p2;
			b = p1;
		}
	}
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
		return a + ((b - a) * uniform(0.0, 1.0, rnd));
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


struct Wall {
	Line line;
	Entity[] rooms;
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

double angleOf(Point p) pure {
	auto a = atan2(cast(real)p.x, cast(real)p.y);
	if (a < 0) {
		a += PI;
	}
	return a;
}

double angleLines(Line a, Line b) pure {
	if (a.a == b.a) {
		return angle3(a.b, a.a, b.b);
	}
	if (a.b == b.a) {
		return angle3(a.a, a.b, b.b);
	}
	if (a.a == b.b) {
		return angle3(a.b, a.a, b.a);
	}
	if (a.b == b.b) {
		return angle3(a.a, a.b, b.a);
	}
	enforce(false, "lines must share a vertex in order to calculate angle");
	assert(0);
}

double angle3(Point a, Point vertex, Point b) pure {
	auto a1 = a - vertex;
	auto b1 = b - vertex;
	// Depending on angleOf, each could be as low as -2PI + epsilon
	// So we could get down to -4*PI
	return ((angleOf(a) - angleOf(b)) + (16*PI)) % (2*PI);
}

/*
unittest {
	import std.conv;
	auto a = angle3(
				Point(4, 0, 0),
				Point(0, 0, 0),
				Point(0, 5, 0));
	assert(approxEqual(a, PI * 1.5, 0.01), a.to!string);
	assert(
			approxEqual(angle3(
				Point(4, 0, 0),
				Point(1, 0, 0),
				Point(1, 5, 0)),
			PI * 1.5, 0.01));
}
*/
