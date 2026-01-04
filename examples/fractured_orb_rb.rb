# frozen_string_literal: true

# Fractured Orb (RLSL Ruby Mode)
# Original: https://www.shadertoy.com/view/ttycWW
# A mashup of 'Crystal Tetrahedron' and 'Buckyball Fracture'
# License: Creative Commons Attribution-NonCommercial-ShareAlike 3.0
# https://creativecommons.org/licenses/by-nc-sa/3.0/deed.en

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "rbgl"
require "rlsl"

WIDTH = 640
HEIGHT = 480

shader = RLSL.define(:fractured_orb_ruby) do
  uniforms do
    float :time
    float :rand_seed
  end

  functions do
    # Helper functions
    define :pR, returns: :vec2, params: { p: :vec2, a: :float }
    define :smax, returns: :float, params: { a: :float, b: :float, r: :float }
    define :vmax2, returns: :float, params: { v: :vec2 }
    define :vmax3, returns: :float, params: { v: :vec3 }
    define :fBox2, returns: :float, params: { p: :vec2, b: :vec2 }
    define :fBox3, returns: :float, params: { p: :vec3, b: :vec3 }
    define :erot, returns: :vec3, params: { p: :vec3, ax: :vec3, ro: :float }
    define :spectrum, returns: :vec3, params: { n: :float }
    define :expImpulse, returns: :float, params: { x: :float, k: :float }
    define :boolSign, returns: :float, params: { v: :float }
    define :boolSign3, returns: :vec3, params: { v: :vec3 }
    define :icosahedronVertex, returns: :vec3, params: { p: :vec3 }
    define :dodecahedronVertex, returns: :vec3, params: { p: :vec3 }
    define :object_sdf, returns: :float, params: { p: :vec3 }
    define :map_scene, returns: :vec2, params: { p: :vec3, anim_time: :float }
    define :calc_normal, returns: :vec3, params: { pos: :vec3, anim_time: :float }
    define :sphericalMatrix_mul, returns: :vec3, params: { tp: :vec2, v: :vec3 }
    define :light_func, returns: :vec3, params: { origin: :vec3, rayDir: :vec3, envOrientation: :vec2 }
    define :env_func, returns: :vec3, params: { origin: :vec3, rayDir: :vec3, envOrientation: :vec2 }
    define :simple_hash, returns: :float, params: { seed: :float }
  end

  helpers do
    # Constants
    PHI = 1.618033988749895
    OUTER = 0.35
    INNER = 0.24

    # pR - 2D rotation
    def pR(p, a)
      c = cos(a)
      s = sin(a)
      vec2(c * p.x + s * p.y, 0.0 - s * p.x + c * p.y)
    end

    # smax - smooth maximum
    def smax(a, b, r)
      ua = max(r + a, 0.0)
      ub = max(r + b, 0.0)
      min(0.0 - r, max(a, b)) + sqrt(ua * ua + ub * ub)
    end

    # vmax
    def vmax2(v)
      max(v.x, v.y)
    end

    def vmax3(v)
      max(max(v.x, v.y), v.z)
    end

    # fBox - box SDF
    def fBox2(p, b)
      d = vec2(abs(p.x) - b.x, abs(p.y) - b.y)
      mx = vec2(max(d.x, 0.0), max(d.y, 0.0))
      mn = vec2(min(d.x, 0.0), min(d.y, 0.0))
      length(mx) + vmax2(mn)
    end

    def fBox3(p, b)
      d = vec3(abs(p.x) - b.x, abs(p.y) - b.y, abs(p.z) - b.z)
      mx = vec3(max(d.x, 0.0), max(d.y, 0.0), max(d.z, 0.0))
      mn = vec3(min(d.x, 0.0), min(d.y, 0.0), min(d.z, 0.0))
      length(mx) + vmax3(mn)
    end

    # erot - rotate on axis
    def erot(p, ax, ro)
      d = ax.x * p.x + ax.y * p.y + ax.z * p.z
      dax = vec3(ax.x * d, ax.y * d, ax.z * d)
      c = cos(ro)
      s = sin(ro)
      # cross(ax, p)
      cx = ax.y * p.z - ax.z * p.y
      cy = ax.z * p.x - ax.x * p.z
      cz = ax.x * p.y - ax.y * p.x
      # mix(dax, p, c) + s * cross
      vec3(
        dax.x + (p.x - dax.x) * c + s * cx,
        dax.y + (p.y - dax.y) * c + s * cy,
        dax.z + (p.z - dax.z) * c + s * cz
      )
    end

    # Spectrum palette (IQ)
    def spectrum(n)
      # a + b * cos(TAU * (c * n + d))
      t = TAU * n
      vec3(
        0.5 + 0.5 * cos(t + 0.0),
        0.5 + 0.5 * cos(t + TAU * 0.33),
        0.5 + 0.5 * cos(t + TAU * 0.67)
      )
    end

    # expImpulse
    def expImpulse(x, k)
      h = k * x
      h * exp(1.0 - h)
    end

    # boolSign
    def boolSign(v)
      if v > 0.0
        1.0
      else
        0.0 - 1.0
      end
    end

    def boolSign3(v)
      vec3(boolSign(v.x), boolSign(v.y), boolSign(v.z))
    end

    # Icosahedron vertex (optimized by iq)
    def icosahedronVertex(p)
      ap = vec3(abs(p.x), abs(p.y), abs(p.z))
      v = vec3(PHI, 1.0, 0.0)
      test1 = ap.x + ap.z * PHI
      dot1 = ap.x * v.x + ap.y * v.y + ap.z * v.z
      if test1 > dot1
        v = vec3(1.0, 0.0, PHI)
      end
      test2 = ap.z + ap.y * PHI
      dot2 = ap.x * v.x + ap.y * v.y + ap.z * v.z
      if test2 > dot2
        v = vec3(0.0, PHI, 1.0)
      end
      bs = boolSign3(p)
      vec3(v.x * 0.52573111 * bs.x, v.y * 0.52573111 * bs.y, v.z * 0.52573111 * bs.z)
    end

    # Dodecahedron vertex (optimized by iq)
    def dodecahedronVertex(p)
      ap = vec3(abs(p.x), abs(p.y), abs(p.z))
      v = vec3(PHI, PHI, PHI)
      v2 = vec3(0.0, 1.0, PHI + 1.0)
      # v2.yzx = (1.0, PHI+1.0, 0.0)
      v3 = vec3(1.0, PHI + 1.0, 0.0)
      # v2.zxy = (PHI+1.0, 0.0, 1.0)
      v4 = vec3(PHI + 1.0, 0.0, 1.0)

      dotv = ap.x * v.x + ap.y * v.y + ap.z * v.z
      dotv2 = ap.x * v2.x + ap.y * v2.y + ap.z * v2.z
      if dotv2 > dotv
        v = v2
      end
      dotv = ap.x * v.x + ap.y * v.y + ap.z * v.z
      dotv3 = ap.x * v3.x + ap.y * v3.y + ap.z * v3.z
      if dotv3 > dotv
        v = v3
      end
      dotv = ap.x * v.x + ap.y * v.y + ap.z * v.z
      dotv4 = ap.x * v4.x + ap.y * v4.y + ap.z * v4.z
      if dotv4 > dotv
        v = v4
      end
      bs = boolSign3(p)
      vec3(v.x * 0.35682209 * bs.x, v.y * 0.35682209 * bs.y, v.z * 0.35682209 * bs.z)
    end

    # Object SDF
    def object_sdf(p)
      d = length(p) - OUTER
      max(d, 0.0 - d - (OUTER - INNER))
    end

    # Map function
    def map_scene(p, anim_time)
      scale = 2.5
      p = vec3(p.x / scale, p.y / scale, p.z / scale)

      outerBound = length(p) - OUTER

      spin = anim_time * (PI / 2.0) - 0.15
      rotated = pR(vec2(p.x, p.z), spin)
      p = vec3(rotated.x, p.y, rotated.y)

      # Buckyball faces
      va = icosahedronVertex(p)
      vb = dodecahedronVertex(p)

      # cross(va, vb)
      cx = va.y * vb.z - va.z * vb.y
      cy = va.z * vb.x - va.x * vb.z
      cz = va.x * vb.y - va.y * vb.x
      side = boolSign(p.x * cx + p.y * cy + p.z * cz)
      r = TAU / 5.0 * side
      vc = erot(vb, va, r)
      vd = erot(vb, va, 0.0 - r)

      d = 1000000.0
      pp = p

      i = 0.0
      while i < 4.0
        # Animation
        t = mod(anim_time * 2.0 / 3.0 + 0.25 - (va.x + 0.0 - va.y) / 30.0, 1.0)
        if t < 0.0
          t = t + 1.0
        end
        t2 = clamp(t * 5.0 - 1.7, 0.0, 1.0)
        explode = 1.0 - pow(1.0 - t2, 10.0)
        explode = explode * (1.0 - pow(t2, 5.0))
        explode = explode + (smoothstep(0.32, 0.34, t) - smoothstep(0.34, 0.5, t)) * 0.05
        explode = explode * 1.4
        t2 = max(t - 0.53, 0.0) * 1.2
        wobble = sin(expImpulse(t2, 20.0) * 2.2 + pow(3.0 * t2, 1.5) * 2.0 * TAU - PI) * smoothstep(0.4, 0.0, t2) * 0.2
        anim = wobble + explode
        p = vec3(pp.x - va.x * anim / 2.8, pp.y - va.y * anim / 2.8, pp.z - va.z * anim / 2.8)

        # Build boundary edge of face
        diffB = vec3(vb.x - va.x, vb.y - va.y, vb.z - va.z)
        normB = normalize(diffB)
        edgeA = p.x * normB.x + p.y * normB.y + p.z * normB.z

        diffC = vec3(vc.x - va.x, vc.y - va.y, vc.z - va.z)
        normC = normalize(diffC)
        edgeB = p.x * normC.x + p.y * normC.y + p.z * normC.z

        diffD = vec3(vd.x - va.x, vd.y - va.y, vd.z - va.z)
        normD = normalize(diffD)
        edgeC = p.x * normD.x + p.y * normD.y + p.z * normD.z

        edge = max(max(edgeA, edgeB), edgeC) - 0.005

        d = min(d, smax(object_sdf(p), edge, 0.002))

        p = pp

        # Cycle faces
        va2 = va
        va = vb
        vb = vc
        vc = vd
        vd = va2

        i = i + 1.0
      end

      bound = outerBound - 0.002
      if bound * scale > 0.002
        d = min(d, bound)
      end

      vec2(d * scale, 1.0)
    end

    # Normal calculation
    def calc_normal(pos, anim_time)
      n = vec3(0.0, 0.0, 0.0)
      k = 0.5773
      e0 = vec3(k * (0.0 - 1.0), k * (0.0 - 1.0), k * (0.0 - 1.0))
      e1 = vec3(k * (0.0 - 1.0), k * 1.0, k * 1.0)
      e2 = vec3(k * 1.0, k * (0.0 - 1.0), k * 1.0)
      e3 = vec3(k * 1.0, k * 1.0, k * (0.0 - 1.0))

      d0 = map_scene(vec3(pos.x + 0.001 * e0.x, pos.y + 0.001 * e0.y, pos.z + 0.001 * e0.z), anim_time).x
      d1 = map_scene(vec3(pos.x + 0.001 * e1.x, pos.y + 0.001 * e1.y, pos.z + 0.001 * e1.z), anim_time).x
      d2 = map_scene(vec3(pos.x + 0.001 * e2.x, pos.y + 0.001 * e2.y, pos.z + 0.001 * e2.z), anim_time).x
      d3 = map_scene(vec3(pos.x + 0.001 * e3.x, pos.y + 0.001 * e3.y, pos.z + 0.001 * e3.z), anim_time).x

      n = vec3(
        e0.x * d0 + e1.x * d1 + e2.x * d2 + e3.x * d3,
        e0.y * d0 + e1.y * d1 + e2.y * d2 + e3.y * d3,
        e0.z * d0 + e1.z * d1 + e2.z * d2 + e3.z * d3
      )
      normalize(n)
    end

    # Spherical matrix multiply
    def sphericalMatrix_mul(tp, v)
      theta = tp.x
      phi = tp.y
      cx = cos(theta)
      cy = cos(phi)
      sx = sin(theta)
      sy = sin(phi)
      vec3(
        cy * v.x + (0.0 - sy) * (0.0 - sx) * v.y + (0.0 - sy) * cx * v.z,
        cx * v.y + sx * v.z,
        sy * v.x + cy * (0.0 - sx) * v.y + cy * cx * v.z
      )
    end

    # Light function
    def light_func(origin, rayDir, envOrientation)
      org = vec3(0.0 - origin.x, 0.0 - origin.y, 0.0 - origin.z)
      rd = vec3(0.0 - rayDir.x, 0.0 - rayDir.y, 0.0 - rayDir.z)
      org = sphericalMatrix_mul(envOrientation, org)
      rd = sphericalMatrix_mul(envOrientation, rd)

      pos = vec3(0.0 - 6.0, 0.0 - 6.0, 0.0 - 6.0)
      normal = normalize(pos)
      up = normalize(vec3(0.0 - 1.0, 1.0, 0.0))

      denom = rd.x * normal.x + rd.y * normal.y + rd.z * normal.z

      result = vec3(0.0, 0.0, 0.0)

      if abs(denom) >= 0.0001
        diff = vec3(pos.x - org.x, pos.y - org.y, pos.z - org.z)
        t = (diff.x * normal.x + diff.y * normal.y + diff.z * normal.z) / denom

        if t >= 0.0
          point = vec3(org.x + t * rd.x - pos.x, org.y + t * rd.y - pos.y, org.z + t * rd.z - pos.z)
          # cross(normal, up)
          tangent_x = normal.y * up.z - normal.z * up.y
          tangent_y = normal.z * up.x - normal.x * up.z
          tangent_z = normal.x * up.y - normal.y * up.x
          tangent = vec3(tangent_x, tangent_y, tangent_z)
          # cross(normal, tangent)
          bitangent = vec3(
            normal.y * tangent.z - normal.z * tangent.y,
            normal.z * tangent.x - normal.x * tangent.z,
            normal.x * tangent.y - normal.y * tangent.x
          )
          uv_l = vec2(
            tangent.x * point.x + tangent.y * point.y + tangent.z * point.z,
            bitangent.x * point.x + bitangent.y * point.y + bitangent.z * point.z
          )

          l = smoothstep(0.75, 0.0, fBox2(uv_l, vec2(0.5, 2.0)) - 1.0)
          l = l * smoothstep(6.0, 0.0, length(uv_l))
          result = vec3(l, l, l)
        end
      end

      result
    end

    # Environment function
    def env_func(origin, rayDir, envOrientation)
      origin = vec3(0.0 - origin.x, 0.0 - origin.y, 0.0 - origin.z)
      rayDir = vec3(0.0 - rayDir.x, 0.0 - rayDir.y, 0.0 - rayDir.z)
      origin = sphericalMatrix_mul(envOrientation, origin)
      rayDir = sphericalMatrix_mul(envOrientation, rayDir)

      l = smoothstep(0.0, 1.7, rayDir.x * 0.5 + rayDir.y * (0.0 - 0.3) + rayDir.z * 1.0) * 0.4
      vec3(0.9 * l, 0.83 * l, 1.0 * l)
    end

    # Simple hash
    def simple_hash(seed)
      fract(sin(seed * 12.9898) * 43758.5453)
    end
  end

  fragment do |frag_coord, resolution, u|
    duration = 10.0 / 3.0
    anim_time = mod(u.time / duration, 1.0)

    envOrientation = vec2(
      (81.5 / 187.0 * 2.0 - 1.0) * 2.0,
      (119.0 / 187.0 * 2.0 - 1.0) * 2.0
    )

    # UV (same as Metal: frag_coord / resolution.y)
    uv = vec2(frag_coord.x / resolution.y, frag_coord.y / resolution.y)

    # Shadertoy-style centered UV
    screen_uv = vec2(uv.x - resolution.x / resolution.y * 0.5, uv.y - 0.5)

    col = vec3(0.0, 0.0, 0.0)
    bgCol = vec3(0.9 * 0.22, 0.83 * 0.22, 1.0 * 0.22)

    maxDist = 30.0
    camOrigin = vec3(0.0, 0.0, 25.0)
    camDir = normalize(vec3(screen_uv.x * 0.168, screen_uv.y * 0.168, 0.0 - 1.0))

    # First march for depth
    firstLen = 0.0
    firstResY = 0.0
    len = 0.0
    dist = 0.0
    mi = 0.0
    p = vec3(0.0, 0.0, 0.0)
    res = vec2(0.0, 0.0)
    while mi < 300.0
      len = len + dist * 0.8
      p = vec3(camOrigin.x + len * camDir.x, camOrigin.y + len * camDir.y, camOrigin.z + len * camDir.z)
      res = map_scene(p, anim_time)
      dist = res.x
      if dist < 0.001
        firstResY = res.y
        break
      end
      if len >= maxDist
        len = maxDist
        firstResY = 0.0
        break
      end
      mi = mi + 1.0
    end
    firstLen = len
    firstP = vec3(camOrigin.x + len * camDir.x, camOrigin.y + len * camDir.y, camOrigin.z + len * camDir.z)

    # Dispersion loop (3 samples for CPU, original uses 5)
    maxDisperse = 3.0
    disperse = 0.0
    while disperse < maxDisperse
      invert = 1.0
      sam = vec3(0.0, 0.0, 0.0)
      origin = camOrigin
      rayDir = camDir

      extinctionDist = 0.0
      wavelength = disperse / maxDisperse

      rand_val = simple_hash(u.rand_seed + disperse * 0.1 + uv.x * 100.0 + uv.y * 1000.0)
      wavelength = wavelength + (rand_val * 2.0 - 1.0) * 0.1

      bounceCount = 0.0

      bounce = 0.0
      hitLen = 0.0
      hitResY = 0.0
      while bounce < 5.0
        if bounce < 0.5
          hitLen = firstLen
          hitResY = firstResY
          p = firstP
        else
          # March
          len2 = 0.0
          dist2 = 0.0
          hitResY = 0.0
          mi2 = 0.0
          while mi2 < 150.0
            len2 = len2 + dist2
            p = vec3(origin.x + len2 * rayDir.x, origin.y + len2 * rayDir.y, origin.z + len2 * rayDir.z)
            res2 = map_scene(p, anim_time)
            dist2 = res2.x * invert
            if dist2 < 0.001
              hitResY = res2.y
              break
            end
            if len2 >= maxDist / 2.0
              len2 = maxDist / 2.0
              hitResY = 0.0
              break
            end
            mi2 = mi2 + 1.0
          end
          hitLen = len2
        end

        if invert < 0.0
          extinctionDist = extinctionDist + hitLen
        end

        if hitResY < 0.001
          break
        end

        nor = calc_normal(p, anim_time)
        nor = vec3(nor.x * invert, nor.y * invert, nor.z * invert)
        ref = reflect(rayDir, nor)

        # Shade
        light = light_func(p, ref, envOrientation)
        sam = vec3(sam.x + light.x * 0.5, sam.y + light.y * 0.5, sam.z + light.z * 0.5)
        fresnel = 1.0 - abs(rayDir.x * nor.x + rayDir.y * nor.y + rayDir.z * nor.z)
        fresnel5 = pow(fresnel, 5.0) * 0.1
        sam = vec3(sam.x + fresnel5, sam.y + fresnel5, sam.z + fresnel5)
        sam = vec3(sam.x * 0.85, sam.y * 0.85, sam.z * 0.98)

        # Refract
        ior = mix(1.2, 1.8, wavelength)
        if invert < 0.0
          ior = ior
        else
          ior = 1.0 / ior
        end

        raf = refract(rayDir, nor, ior)
        tif = length(raf) < 0.001
        if tif
          rayDir = ref
        else
          rayDir = raf
        end

        dotRN = abs(rayDir.x * nor.x + rayDir.y * nor.y + rayDir.z * nor.z)
        offset = 0.01 / (dotRN + 0.0001)
        origin = vec3(p.x + offset * rayDir.x, p.y + offset * rayDir.y, p.z + offset * rayDir.z)
        invert = invert * (0.0 - 1.0)

        bounceCount = bounce

        bounce = bounce + 1.0
      end

      # Add background or environment
      if bounceCount < 0.5
        sam = vec3(sam.x + bgCol.x, sam.y + bgCol.y, sam.z + bgCol.z)
      else
        env = env_func(firstP, rayDir, envOrientation)
        sam = vec3(sam.x + env.x, sam.y + env.y, sam.z + env.z)
      end

      # Accumulate color with spectrum weighting
      if bounceCount < 0.5
        # No hit - add background with boost and break early
        col = vec3(col.x + sam.x * maxDisperse / 2.0, col.y + sam.y * maxDisperse / 2.0, col.z + sam.z * maxDisperse / 2.0)
        break
      else
        spec = spectrum(0.0 - wavelength + 0.25)
        col = vec3(col.x + sam.x * spec.x, col.y + sam.y * spec.y, col.z + sam.z * spec.z)
      end

      disperse = disperse + 1.0
    end

    # Average over dispersion samples
    col = vec3(col.x / maxDisperse, col.y / maxDisperse, col.z / maxDisperse)

    # Tonemap
    col = vec3(pow(col.x, 1.25) * 2.5, pow(col.y, 1.25) * 2.5, pow(col.z, 1.25) * 2.5)
    col = vec3(col.x / 2.0 * 16.0, col.y / 2.0 * 16.0, col.z / 2.0 * 16.0)
    col = vec3(max(0.0, col.x - 0.004), max(0.0, col.y - 0.004), max(0.0, col.z - 0.004))
    col = vec3(
      (col.x * (6.2 * col.x + 0.5)) / (col.x * (6.2 * col.x + 1.7) + 0.06),
      (col.y * (6.2 * col.y + 0.5)) / (col.y * (6.2 * col.y + 1.7) + 0.06),
      (col.z * (6.2 * col.z + 0.5)) / (col.z * (6.2 * col.z + 1.7) + 0.06)
    )

    col
  end
end

# Initialize display
window = RBGL::GUI::Window.new(width: WIDTH, height: HEIGHT, title: "Fractured Orb (Ruby Mode)")

puts "Fractured Orb (RLSL Ruby Mode)"
puts "Original: https://www.shadertoy.com/view/ttycWW"
puts "License: Creative Commons Attribution-NonCommercial-ShareAlike 3.0"
puts "https://creativecommons.org/licenses/by-nc-sa/3.0/deed.en"
puts "Note: Simplified version (3 dispersion samples, 5 bounces) for CPU performance"
puts "Press 'q' or Escape to quit"

start_time = Time.now
frame_count = 0
last_fps_time = start_time
running = true

buffer = "\x00" * (WIDTH * HEIGHT * 4)

while running && !window.should_close?
  time = Time.now - start_time
  rand_seed = rand * 1000.0

  shader.render(buffer, WIDTH, HEIGHT, { time: time, rand_seed: rand_seed })

  window.set_pixels(buffer)

  events = window.poll_events_raw
  events.each do |e|
    if e[:type] == :key_press && (e[:key] == 12 || e[:key] == "q")
      running = false
    end
  end

  frame_count += 1
  now = Time.now
  if now - last_fps_time >= 1.0
    fps = frame_count / (now - last_fps_time)
    puts "FPS: #{fps.round(1)}"
    frame_count = 0
    last_fps_time = now
  end
end

window.close
