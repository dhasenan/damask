module dmud.util;

public import core.thread : Fiber;

import core.thread;
import std.algorithm;
import std.concurrency;
import std.encoding;
import std.exception;
import std.format;
import std.range;

import jsonizer;

@safe:

mixin template JsonSupport() {
	@trusted { mixin JsonizeMe; }
}

@trusted void spawn(void delegate() @safe dg) {
	assert(!!scheduler);
	scheduler.spawn(dg);
}

@trusted void yield() {
	scheduler.yield();
}

@trusted Fiber getRunning() {
	return Fiber.getThis();
}

Point randomPointInCircle(TRng)(ref TRng rng, double radius) {
	import std.math : PI, sqrt;
	import std.random : uniform;
	auto angle = uniform(0.0, 2 * PI, rng);
	auto r = uniform(0, radius ^^ 2, rng).sqrt;
	return toCoords(angle, r);
}

Point toCoords(double angle, double length, long height = 0) {
	import std.math : PI, sin, cos, lrint, abs;
	Point p;
	p.z = height;
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

struct Point {
	mixin JsonSupport;

	@jsonize {
		long x, y, z;
	}
	string toString() { return "(%s, %s, %s)".format(x, y, z); }

	double dist(const ref Point other) {
		auto dx = x - other.x;
		auto dy = y - other.y;
		auto dz = z - other.z;
		return (dx^^2 + dy^^2 + dz^^2) ^^ 0.5;
	}

	bool adjacent(Point other) {
		auto dx = x - other.x;
		auto dy = y - other.y;
		auto dz = z - other.z;
		// We have eight directions on the plane, plus up and down.
		if ((dz == -1 || dz == 1) && dx == 0 && dy == 0) {
			return true;
		}
		return
			dz == 0 &&
			1 >= dx &&
			-1 <= dx &&
			1 >= dy &&
			-1 <= dy;
	}

	Point opBinary(string op)(Point other) if (op == "-") {
		return Point(
				this.x - other.x,
				this.y - other.y,
				this.z - other.z);
	}

	Point opBinary(string op)(Point other) if (op == "+") {
		return Point(
				this.x + other.x,
				this.y + other.y,
				this.z + other.z);
	}

	Point opBinary(string op)(double s) if (op == "*") {
		return Point(
				cast(long)(this.x * s),
				cast(long)(this.y * s),
				cast(long)(this.z * s));
	}

	Point opOpAssign(string op)(const ref Point other) if (op == "+") {
		x += other.x;
		y += other.y;
		z += other.z;
		return this;
	}

  auto neighbors() {
    return
      cartesianProduct(iota(-1, 2), iota(-1, 2))
        .filter!(k => k[0] != 0 || k[1] != 0)
        .map!(k => Point(k[0] + x, k[1] + y, z));
  }
}

/// A cubic array with *centered* coordinates
struct Cube(T) {
	private {
		int _radius;
		int _off;
		int _dim;
		T[] _data;
	}

	this(int radius) {
		enforce(radius >= 1, "Cubes must have a radius of at least 1");
		_radius = radius;
		// We want enough room to hold a center point, {radius} elements around, plus a margin of one.
		_dim = (_radius + 1) * 2 + 1;
		// how to get to the center
		_off = _radius + 2;
		_data = new T[_dim * _dim * _dim];
	}

	int radius() const @property { return _radius; }

	private long _index(long x, long y, long z) {
		enforce(x <= _radius
			&& y <= _radius
			&& x >= -_radius
			&& y >= -_radius
			&& z <= _radius
			&& z >= -_radius,
			"(%s, %s, %s) violates radius %s".format(x, y, z, _radius));
		return ((x + _off) * _dim + y + _off) * _dim + z + _off;
	}

	T opIndex(long x, long y, long z) {
		return _data[_index(x, y, z)];
	}

	T opIndexAssign(T item, long x, long y, long z) {
		return _data[_index(x, y, z)] = item;
	}

	T opIndexAssign(T item, Point p) {
		return _data[_index(p.x, p.y, p.z)] = item;
	}

	T opIndex(Point p) {
		return _data[_index(p.x, p.y, p.z)];
	}

  bool contains(Point p) {
    return inBounds(p) && _data[_index(p.x, p.y, p.z)] != T.init;
  }

  bool inBounds(Point p) {
    auto i = _index(p.x, p.y, p.z);
    return i >= 0 && i < _data.length;
  }

	int opApply(int delegate(Point, T) @safe dg) {
		for (long x = -_radius; x <= _radius; x++) {
			for (long y = -_radius; y <= _radius; y++) {
				auto p = Point(x, y);
				int a = dg(p, this[p]);
				if (a) return a;
			}
		}
		return 0;
	}

  /// Returns: range of T
	auto nonDefaults() {
		return _data.filter!(x => x != T.init);
	}
}

unittest {
	auto s = Cube!(int)(5);
	s[1, 2, -2] = 4;
	assert(s[1, 2, -2] == 4);
	assert(s[-1, -2, 4] == 0);  // default
	s[-5, -5, 3] = 3;
	assert(s[-5, -5, 3] == 3);
	s[-3, -5, 3] = 3;
	assert(s[-3, -5, 3] == 3);
	s[Point(4, -2, 1)] = 188;
	assert(s[4, -2, 1] == 188);
	assert(s[Point(4, -2, 1)] == 188);
	s[0, 0, 0] = -14;
	assert(s[0, 0, 0] == -14);
}


EncodingScheme ascii;
EncodingScheme iso8859_1;
EncodingScheme utf8;
EncodingScheme utf32;

static this() @trusted {
	ascii = EncodingScheme.create("ascii");
	utf8 = EncodingScheme.create("utf-8");
	iso8859_1 = EncodingScheme.create("ISO-8859-1");
	utf32 = EncodingScheme.create("utf-32le");
}

