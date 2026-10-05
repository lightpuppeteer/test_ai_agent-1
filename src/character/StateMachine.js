/**
 * Minimal, explicit finite state machine.
 *
 *  - States are classes with optional lifecycle hooks.
 *  - Allowed transitions are declared up-front in a table; anything else is
 *    rejected (and logged in dev), which keeps complex interaction flows
 *    (sit → stand → drive…) honest.
 *  - Transitions requested *during* a state's update are deferred until that
 *    update returns, so a state never runs code after it has been exited.
 */
export class State {
  /** @param {string} name */
  constructor(name) {
    this.name = name;
    /** @type {StateMachine} */
    this.machine = null;
    this.elapsed = 0;
  }

  /** The entity that owns the machine (e.g. the CharacterController). */
  get owner() {
    return this.machine.owner;
  }

  /** @param {State|null} _previous @param {object} _params */
  enter(_previous, _params) {}
  /** @param {State|null} _next */
  exit(_next) {}
  /** Fixed-rate (physics) update. */
  fixedUpdate(_dt) {}
  /** Per-frame update (input edges, animation, presentation). */
  update(_dt) {}
  /** Return false to veto leaving this state for `to`. */
  canExit(_to) {
    return true;
  }
}

export class StateMachine {
  /**
   * @param {object} owner
   * @param {Record<string, string[]>} transitions allowed targets per state ('*' = any)
   */
  constructor(owner, transitions) {
    this.owner = owner;
    this.transitions = transitions;
    this.states = new Map();
    this.current = null;
    this.previous = null;
    this._pending = null;
    this._updating = false;
    this.listeners = new Set();
    this.debug = typeof import.meta !== 'undefined' && !!import.meta.env?.DEV;
  }

  add(state) {
    state.machine = this;
    this.states.set(state.name, state);
    return this;
  }

  get(name) {
    return this.states.get(name);
  }

  is(...names) {
    return !!this.current && names.includes(this.current.name);
  }

  can(to) {
    if (!this.current) return true;
    const allowed = this.transitions[this.current.name] ?? [];
    return (allowed.includes('*') || allowed.includes(to)) && this.current.canExit(to);
  }

  /**
   * Requests a transition. Returns false if it is not allowed.
   * @param {string} to
   * @param {object} [params] passed to the next state's enter()
   */
  transition(to, params = {}) {
    if (!this.states.has(to)) throw new Error(`FSM: unknown state "${to}"`);
    if (!this.can(to)) {
      if (this.debug) console.warn(`FSM: transition ${this.current?.name} → ${to} rejected`);
      return false;
    }
    if (this._updating) {
      this._pending = { to, params };
      return true;
    }
    this._apply(to, params);
    return true;
  }

  _apply(to, params) {
    const next = this.states.get(to);
    const prev = this.current;
    prev?.exit(next);
    this.previous = prev;
    this.current = next;
    next.elapsed = 0;
    next.enter(prev, params);
    for (const l of this.listeners) l(next.name, prev?.name ?? null);
  }

  _run(fn) {
    if (!this.current) return;
    this._updating = true;
    try {
      fn(this.current);
    } finally {
      this._updating = false;
    }
    // Apply at most a few chained transitions per tick.
    for (let i = 0; i < 4 && this._pending; i++) {
      const { to, params } = this._pending;
      this._pending = null;
      this._updating = true;
      try {
        this._apply(to, params);
      } finally {
        this._updating = false;
      }
    }
  }

  fixedUpdate(dt) {
    this._run((s) => s.fixedUpdate(dt));
  }

  update(dt) {
    this._run((s) => {
      s.elapsed += dt;
      s.update(dt);
    });
  }

  onChange(fn) {
    this.listeners.add(fn);
    return () => this.listeners.delete(fn);
  }
}
