module dmud.component;

import jsonizer.jsonize;

import std.conv;
import std.typecons;

alias Entity = Typedef!(ulong, 0, "Entity");
enum None = cast(Entity)0;

T get(T)(Entity entity) {
	return ComponentManager.instance.get!(T)(entity);
}

T add(T)(Entity entity) {
	auto t = new T;
	ComponentManager.instance.add!(T)(entity, t);
	return t;
}

T add(T)(Entity entity, T value) {
	ComponentManager.instance.add!(T)(t);
	return t;
}

class Component {
	mixin JsonizeMe;

	Entity entity;
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

	void removeComponent(T)(Entity entity) if (is(T : Component)) {
		auto p = entity in _components;
		if (p) {
			(*p).remove(T.classinfo);
		}
	}

	void removeEntity(Entity entity) {
		_components.remove(entity);
	}

	const(Component[]) components(Entity entity) {
		auto p = entity in _components;
		if (p) { return p.values; }
		return null;
	}

	@property
	const(Entity[]) entities() {
		return _components.keys;
	}
}
