module dmud.component;

import jsonizer;

import std.conv;
import std.json;
import std.typecons;

import dmud.util;

@safe:

struct Entity {
	mixin JsonSupport;
	@jsonize ulong value;
	this(ulong v) { value = v; }
}
enum None = Entity(0);
enum Invalid = Entity(ulong.max);

T get(T)(Entity entity) {
	return ComponentManager.instance.get!(T)(entity);
}

T add(T)(Entity entity) {
	auto t = new T;
  t.entity = entity;
	ComponentManager.instance.add!(T)(entity, t);
	return t;
}

T add(T)(Entity entity, T value) {
  value.entity = entity;
	ComponentManager.instance.add!(T)(t);
	return t;
}

class Component {
	@trusted {
		mixin JsonizeMe;
	}

	@jsonize("class") @property {
		// This is a hack to support class hierarchies.
		string className() { return this.classinfo.name; }
		void className(string ignored) {}
	}

	@jsonize Entity entity;
	bool canSave = true;
}

class ComponentManager {
	private static ComponentManager _instance;
	static ComponentManager instance() {
		if (!_instance) {
			_instance = new ComponentManager();
		}
		return _instance;
	}
	private Component[ClassInfo][Entity] _components;
	/// Next entity that will be allocated.
	/// The first entity should always be the world.
	/// Entity 0 is special (the "none" entity).
	// TODO: reserve specific ranges for different purposes.
	// For instance, the first 48 bit range for static world data, the next 48 for player data
	// (including inventories), the last range for ephemeral stuff, etc.
	private ulong _next = 1;

	Entity next()
	out (result) {
		assert(result != None);
	}
	body {
		return to!Entity(_next++);
	}

	T add(T)(Entity entity, T component) if (is (T : Component))
	in {
		assert(entity != None);
		assert(component.entity == entity || component.entity == None);
	}
	body {
		component.entity = entity;
		ClassInfo ci;
		static if (is (T == Component)) {
			ci = component.classinfo;
		} else {
			ci = T.classinfo;
		}
		auto p = entity in _components;
		if (p) {
			(*p)[ci] = component;
		} else {
			_components[entity] = [component.classinfo: component];
		}
		return component;
	}

	T get(T)(Entity entity) if (is(T : Component)) {
		auto p = entity in _components;
		if (p) {
			auto q = T.classinfo in *p;
			if (q) {
				return cast(T)*q;
			}
		}
		return T.init;
	}

  void load(Entity entity, Component[] components) {
    Component[ClassInfo] c;
    foreach (component; components) {
      import std.format;
      assert(component.entity == entity, "expected entity %s for component %s but got %s".format(entity,
          component.classinfo.name, component.entity));
      c[component.classinfo] = component;
    }
    _components[entity] = c;
  }

	void removeComponent(T)(Entity entity) if (is(T : Component)) {
		auto p = entity in _components;
		if (p) {
			(*p).remove(T.classinfo);
		}
	}

	void removeEntity(Entity entity) {
		_components.remove(entity);
	}

	const(Component[]) components(Entity entity) @trusted {
		auto p = entity in _components;
		if (p) { return p.values; }
		return null;
	}

	/*

	@property
	const(Entity[]) entities() {
		return _components.keys;
	}
  */
}


unittest {
  class Foo : Component {
    string name;
  }
  auto cm = new ComponentManager;
  auto entity = cm.next;
  auto f = new Foo;
  f.name = "hi there";
  cm.add(entity, f);
  assert(f.entity == entity);
  assert(f.entity.value > 0);
  auto f2 = cm.get!Foo(entity);
  assert(f2.name == "hi there");
}
