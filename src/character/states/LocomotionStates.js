import { State } from '../StateMachine.js';

/**
 * Shared on-foot behaviour: KCC movement from intent, jump latching,
 * interaction requests and locomotion-state selection with hysteresis.
 *
 * Idle / Walk / Run are distinct states (so gameplay can hook into each —
 * footstep sets, stamina, idle fidgets…), but the *animation* blends
 * continuously on actual speed inside the rig, so switching never pops.
 */
class GroundedState extends State {
  enter() {
    this.owner.cameraRig.setMode('follow');
  }

  fixedUpdate(dt) {
    const c = this.owner;
    const jumped = c.moveGrounded(dt, { jump: c.jumpRequested });
    c.jumpRequested = false;
    if (jumped || (!c.body.grounded && c.body.airTime > 0.15)) {
      this.machine.transition('airborne', { jumped });
    }
  }

  update() {
    const c = this.owner;
    if (c.input.consume('jump')) c.jumpRequested = true;
    if (c.input.consume('interact') && c.tryInteract()) return;
    const next = c.desiredLocomotionState(this.name);
    if (next !== this.name) this.machine.transition(next);
  }
}

export class IdleState extends GroundedState {
  constructor() {
    super('idle');
  }
}

export class WalkState extends GroundedState {
  constructor() {
    super('walk');
  }
}

export class RunState extends GroundedState {
  constructor() {
    super('run');
  }
}

/** Jumping or falling. Lands back into the locomotion state matching intent. */
export class AirborneState extends State {
  constructor() {
    super('airborne');
  }

  enter() {
    this.owner.jumpRequested = false;
  }

  fixedUpdate(dt) {
    const c = this.owner;
    c.moveGrounded(dt, { air: true });
    if (c.body.grounded && c.body.verticalVelocity <= 0) {
      const next = c.desiredLocomotionState('walk');
      this.machine.transition(next === 'walk' && c.intent.magnitude < 0.1 ? 'idle' : next);
    }
  }

  update() {
    // Ignore a jump press made in the air (no buffered double jump).
    this.owner.input.flush('jump');
  }
}
