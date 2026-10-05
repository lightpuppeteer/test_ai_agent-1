import * as THREE from 'three';
import { INPUT_BINDINGS } from '../config.js';

/**
 * Action-based input. Gameplay never reads raw key codes: it asks for
 * actions ("interact", "run"…) so bindings can be remapped and gamepads added
 * later without touching the character or vehicle code.
 *
 * Edge-triggered presses are *latched* (timestamp + frame number) and cleared
 * when consumed. A press stays valid for the next couple of frames *or* a
 * short time window, whichever is longer — so it is never lost on a slow
 * frame or a frame without a physics step, never handled twice, and a stale
 * press from seconds ago can't trigger something unexpected.
 */
export class Input {
  constructor(element, bindings = INPUT_BINDINGS) {
    this.element = element;
    this.bindings = bindings;
    this._codeToActions = new Map();
    for (const [action, codes] of Object.entries(bindings)) {
      for (const code of codes) {
        if (!this._codeToActions.has(code)) this._codeToActions.set(code, []);
        this._codeToActions.get(code).push(action);
      }
    }

    this._down = new Set(); // codes currently held
    this._pressedAt = new Map(); // action -> { time (ms), frame }
    this.frame = 0;
    this._look = new THREE.Vector2();
    this._zoom = 0;
    this._dragging = false;
    this._lastPointer = new THREE.Vector2();
    this.lastLookTime = -Infinity;

    this._onKeyDown = (e) => {
      if (e.repeat) return;
      const actions = this._codeToActions.get(e.code);
      if (!actions) return;
      if (['Space', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight'].includes(e.code)) e.preventDefault();
      this._down.add(e.code);
      const press = { time: performance.now(), frame: this.frame };
      for (const a of actions) this._pressedAt.set(a, press);
    };
    this._onKeyUp = (e) => this._down.delete(e.code);
    this._onBlur = () => this._down.clear();
    this._onPointerDown = (e) => {
      this._dragging = true;
      this._lastPointer.set(e.clientX, e.clientY);
      element.setPointerCapture?.(e.pointerId);
    };
    this._onPointerMove = (e) => {
      if (!this._dragging) return;
      this._look.x += e.clientX - this._lastPointer.x;
      this._look.y += e.clientY - this._lastPointer.y;
      this._lastPointer.set(e.clientX, e.clientY);
      this.lastLookTime = performance.now();
    };
    this._onPointerUp = (e) => {
      this._dragging = false;
      element.releasePointerCapture?.(e.pointerId);
    };
    this._onWheel = (e) => {
      this._zoom += Math.sign(e.deltaY);
      e.preventDefault();
    };

    window.addEventListener('keydown', this._onKeyDown);
    window.addEventListener('keyup', this._onKeyUp);
    window.addEventListener('blur', this._onBlur);
    element.addEventListener('pointerdown', this._onPointerDown);
    element.addEventListener('pointermove', this._onPointerMove);
    element.addEventListener('pointerup', this._onPointerUp);
    element.addEventListener('pointercancel', this._onPointerUp);
    element.addEventListener('wheel', this._onWheel, { passive: false });
    element.addEventListener('contextmenu', (e) => e.preventDefault());
  }

  /** Call once at the start of every rendered frame (Engine global system). */
  beginFrame() {
    this.frame++;
  }

  /** Is any key bound to `action` currently held? */
  isDown(action) {
    const codes = this.bindings[action];
    if (!codes) return false;
    for (const c of codes) if (this._down.has(c)) return true;
    return false;
  }

  /**
   * Returns true once per press of `action`, then clears it. Valid within
   * `maxFrames` rendered frames or `maxAgeMs`, whichever is longer.
   */
  consume(action, { maxAgeMs = 400, maxFrames = 2 } = {}) {
    const p = this._pressedAt.get(action);
    if (p === undefined) return false;
    this._pressedAt.delete(action);
    return this.frame - p.frame <= maxFrames || performance.now() - p.time <= maxAgeMs;
  }

  /** Clears latched presses (e.g. when changing input context). */
  flush(...actions) {
    if (actions.length === 0) this._pressedAt.clear();
    else for (const a of actions) this._pressedAt.delete(a);
  }

  axis(negative, positive) {
    return (this.isDown(positive) ? 1 : 0) - (this.isDown(negative) ? 1 : 0);
  }

  /** WASD as a 2D vector: x = strafe right, y = forward. Length ≤ 1. */
  moveVector(out = new THREE.Vector2()) {
    out.set(this.axis('left', 'right'), this.axis('backward', 'forward'));
    if (out.lengthSq() > 1) out.normalize();
    return out;
  }

  /** Accumulated pointer-drag delta in pixels since the last call. */
  consumeLook(out = new THREE.Vector2()) {
    out.copy(this._look);
    this._look.set(0, 0);
    return out;
  }

  consumeZoom() {
    const z = this._zoom;
    this._zoom = 0;
    return z;
  }

  dispose() {
    window.removeEventListener('keydown', this._onKeyDown);
    window.removeEventListener('keyup', this._onKeyUp);
    window.removeEventListener('blur', this._onBlur);
    const el = this.element;
    el.removeEventListener('pointerdown', this._onPointerDown);
    el.removeEventListener('pointermove', this._onPointerMove);
    el.removeEventListener('pointerup', this._onPointerUp);
    el.removeEventListener('pointercancel', this._onPointerUp);
    el.removeEventListener('wheel', this._onWheel);
  }
}
