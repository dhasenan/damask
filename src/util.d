module dmud.util;

import core.thread;
public import core.thread : Fiber;
import std.concurrency;
import std.algorithm;
import std.exception;
import std.format;

@safe:

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

struct Point {
	long x, y, z;
	string toString() { return "(%s, %s)".format(x, y); }

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
		return 
			1 >= dz &&
			-1 <= dz &&
			1 >= dx &&
			-1 <= dx &&
			1 >= dy &&
			-1 <= dy;
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
		_radius = radius;
		// We want enough room to hold a center point, {radius} elements around, plus a margin of one.
		_dim = (_radius + 1) * 2 + 1;
		// how to get to the center
		_off = _radius + 2;
		_data = new T[_dim * _dim];
	}

	private long _index(long x, long y) {
		enforce(x <= _radius
			&& y <= _radius
			&& x >= -_radius
			&& y >= -_radius,
			"(%s, %s) violates radius %s".format(x, y, _radius));
		return (x + _off) * _dim + y + _off;
	}

	T opIndex(long x, long y) {
		return _data[_index(x, y)];
	}

	T opIndexAssign(T item, long x, long y) {
		return _data[_index(x, y)] = item;
	}

	T opIndexAssign(T item, Point p) {
		return _data[_index(p.x, p.y)] = item;
	}

	T opIndex(Point p) {
		return _data[_index(p.x, p.y)];
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
