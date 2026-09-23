<template>
  <div ref="hatRef" class="hat pb-1" aria-hidden="true">
    <div class="hat__container d-flex align-end">
      <div class="hat__fog 
"></div>
      <div class="hat__flash"></div>
      <div class="hat__clouds hat__clouds--far"></div>
      <div class="hat__shadow hat__shadow--top"></div>
      <div class="hat__clouds hat__clouds--near"></div>

      <div class="hat__warriors ">
        <div class="hat__warrior hat__warrior--one"></div>
        <div class="hat__warrior hat__warrior--two"></div>
        <div class="hat__warrior hat__warrior--three"></div>
      </div>

      <div class="hat__shadow hat__shadow--bottom"></div>
    </div>
  </div>
</template>

<script setup>
import { onMounted, onUnmounted, ref } from "vue"
import { gsap } from "gsap"
import { SlowMo } from "gsap/EasePack"

gsap.registerPlugin(SlowMo)

const hatRef = ref(null)
let animationContext

onMounted(() => {
  animationContext = gsap.context(() => {
    gsap.fromTo(".hat__warrior", { backgroundPositionY: "165px" }, {
      backgroundPositionY: "0px",
      delay: 0.3,
      duration: 0.5,
      ease: "power4.out",
      stagger: 0.2
    })

    gsap.fromTo(".hat__fog", { opacity: 1, scale: 1.1, y: 10 }, {
      opacity: 0,
      scale: 1.8,
      y: -45,
      duration: 6.4,
      ease: "sine.out",
      repeat: -1,
      repeatDelay: 0.3
    })

    gsap.to(".hat__clouds--near", {
      scale: 1.2,
      backgroundPositionX: "-1000px",
      duration: 18,
      ease: "none",
      repeat: -1
    })
    gsap.to(".hat__clouds--far", {
      backgroundPositionX: "-1000px",
      duration: 18,
      ease: "none",
      repeat: -1
    })

gsap.timeline({ repeat: -1 })
  .to(".hat__warriors", {
    filter: "brightness(0.7)",
    duration: 2,
    delay: 1.1,
     ease: "circ.in"
  })
  .to(".hat__flash", {
    opacity: 0.7,
    duration: 0.05
  }, "<")
  .to(".hat__warriors", {
    filter: "brightness(1)",
    duration: 1.4,
    ease: "sine.out"
  })
  .to(".hat__flash", {
    opacity: 0,
    duration: 2.2,
    ease: "sine.out"
  }, "-=2.3", "<")
  .to(".hat__warriors", {
    filter: "brightness(0.7)",
    duration: 0.05,
    delay: 1.4
  })
  .to(".hat__flash", {
    opacity: 1,
    duration: 0.05
  }, "<")
  .to(".hat__warriors", {
    filter: "brightness(1)",
    duration: 1.7,
    ease: "sine.out"
  })
  .to(".hat__flash", {
    opacity: 0,
    duration: 5
  }, "<")
  }, hatRef.value)
})

onUnmounted(() => animationContext?.revert())
</script>

<style scoped>
.hat {
  height: 146px;
  overflow: hidden;
  pointer-events: none;
}

.hat__container {
  position: relative;
  height: 100%;
  overflow: hidden;
  background: #13151a;
  border-bottom: 2px solid rgba(0, 0, 0, 0.4);
}

.hat__warriors {
  position: relative;
  left: 50%;
  z-index: 11;
  display: flex;
  justify-content: center;
  width: 1085px;
  height: 146px;
  background-position: center bottom;
  background-repeat: no-repeat;
  transform: translateX(-50%) scale(clamp(0.72, calc(100vw / 1085px), 1));
  transform-origin: center bottom;
}

.hat__warrior {
  flex: 0 0 auto;
  height: 146px;
  background-repeat: no-repeat;
  background-size: auto 145%;
}

.hat__warrior--one {
  width: 414px;
  background-position: 100% -10px;
  background-image: url("/hat/1war.png");
}

.hat__warrior--two {
  width: 315px;
  background-position: -5px -10px;
  background-image: url("/hat/2war.png");
}

.hat__warrior--three {
  width: 356px;
  background-position: -7px -10px;
  background-image: url("/hat/3war.png");
}

.hat__clouds,
.hat__fog,
.hat__flash,
.hat__shadow {
  position: absolute;
  inset: 0;
}

.hat__clouds {
  background-image: url("/hat/clouds2.png");
  background-repeat: repeat-x;
}

.hat__clouds--far {
  z-index: 2;
  opacity: 0.9;
  background-position: center 0;
  background-size: 800px auto;
}

.hat__clouds--near {
  z-index: 3;
  opacity: 0.3;
  background-position: center 0;
  background-size: 300px auto;
}

.hat__fog {
  z-index: 0;
  background: url("/hat/fog2.jpg") center -0px / cover no-repeat;
}

.hat__flash {
  z-index: 4;
  opacity: 0;
  background: url("/hat/flash2.jpg") center bottom / cover no-repeat;
}

.hat__shadow--top {
  z-index: 5;
  background: linear-gradient(180deg, rgba(0, 0, 0, 0.82), transparent 54%);
}

.hat__shadow--bottom {
  z-index: 6;
  background: linear-gradient(180deg, transparent, rgba(0, 0, 0, 0.4));
}

@media (max-width: 900px) {
  .hat__warriors {
    transform: translateX(-50%) scale(clamp(0.72, calc(100vw / 1085px), 0.82));
  }
}
</style>
