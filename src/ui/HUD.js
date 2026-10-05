/**
 * Minimal DOM HUD: interaction prompt, vehicle gauges, toasts, debug line.
 * Kept framework-free; swap for your UI layer of choice.
 */
export class HUD {
  constructor() {
    const $ = (id) => document.getElementById(id);
    this.root = $('hud');
    this.prompt = $('hud-prompt');
    this.promptLabel = $('hud-prompt-label');
    this.vehiclePanel = $('hud-vehicle');
    this.speedEl = $('hud-speed');
    this.gearEl = $('hud-gear');
    this.rpmEl = $('hud-rpm');
    this.debugEl = $('hud-debug');
    this.helpEl = $('hud-help');
    this.vehicle = null;
    this.state = '';
    this._toastTimer = null;
    this._debugAccum = 0;
  }

  show() {
    this.root.hidden = false;
  }

  /** @param {import('../interaction/Interactable.js').Interactable|null} interactable */
  setPrompt(interactable) {
    if (!interactable) {
      this.prompt.hidden = true;
      return;
    }
    this.promptLabel.textContent = interactable.label;
    this.prompt.hidden = false;
  }

  showVehicle(vehicle) {
    this.vehicle = vehicle;
    this.vehiclePanel.hidden = false;
  }

  hideVehicle() {
    this.vehicle = null;
    this.vehiclePanel.hidden = true;
  }

  toast(text, ms = 1600) {
    let el = document.getElementById('hud-toast');
    if (!el) {
      el = document.createElement('div');
      el.id = 'hud-toast';
      el.className = 'hud__toast';
      this.root.appendChild(el);
    }
    el.textContent = text;
    el.classList.add('is-visible');
    clearTimeout(this._toastTimer);
    this._toastTimer = setTimeout(() => el.classList.remove('is-visible'), ms);
  }

  setDebugState(state) {
    this.state = state;
  }

  toggleHelp() {
    this.helpEl.hidden = !this.helpEl.hidden;
  }

  /** Called every frame. */
  update(dt, engine) {
    if (this.vehicle) {
      const v = this.vehicle;
      this.speedEl.textContent = Math.round(Math.abs(v.speed) * 3.6);
      this.gearEl.textContent = v.gearLabel;
      this.rpmEl.style.width = `${Math.min(100, (v.rpm / v.drivetrain.redline) * 100).toFixed(1)}%`;
    }
    this._debugAccum += dt;
    if (this._debugAccum > 0.25) {
      this._debugAccum = 0;
      this.debugEl.textContent = `${engine.stats.fps} fps · state: ${this.state}`;
    }
  }
}
