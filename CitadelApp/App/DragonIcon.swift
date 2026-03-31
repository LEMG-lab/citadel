import SwiftUI

/// A stylized dragon head silhouette — Smaug guarding the vault.
/// Drawn as a SwiftUI Shape for crisp rendering at any size.
struct DragonIcon: View {
    var size: CGFloat = 64

    var body: some View {
        DragonShape()
            .fill(
                LinearGradient(
                    colors: [Color(red: 0.85, green: 0.65, blue: 0.13),
                             Color(red: 0.72, green: 0.45, blue: 0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .shadow(color: Color(red: 0.85, green: 0.65, blue: 0.13).opacity(0.3), radius: size * 0.06, y: size * 0.03)
    }
}

/// Dragon head profile shape — a heraldic sigil style.
/// Coordinates are in a 0...1 unit square, scaled by the frame.
struct DragonShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height

        var p = Path()

        // --- Head outline (top of skull, curving to snout) ---
        // Start at the back of the skull
        p.move(to: CGPoint(x: 0.62 * w, y: 0.08 * h))

        // Crown/horn ridge
        p.addCurve(
            to: CGPoint(x: 0.48 * w, y: 0.04 * h),
            control1: CGPoint(x: 0.58 * w, y: 0.04 * h),
            control2: CGPoint(x: 0.53 * w, y: 0.02 * h)
        )

        // Top horn
        p.addLine(to: CGPoint(x: 0.40 * w, y: 0.0 * h))
        p.addCurve(
            to: CGPoint(x: 0.35 * w, y: 0.10 * h),
            control1: CGPoint(x: 0.38 * w, y: 0.04 * h),
            control2: CGPoint(x: 0.35 * w, y: 0.07 * h)
        )

        // Forehead down to brow ridge
        p.addCurve(
            to: CGPoint(x: 0.22 * w, y: 0.22 * h),
            control1: CGPoint(x: 0.32 * w, y: 0.14 * h),
            control2: CGPoint(x: 0.26 * w, y: 0.18 * h)
        )

        // Brow ridge (angular, prominent)
        p.addLine(to: CGPoint(x: 0.18 * w, y: 0.20 * h))

        // Eye socket area — slight indent
        p.addCurve(
            to: CGPoint(x: 0.16 * w, y: 0.30 * h),
            control1: CGPoint(x: 0.15 * w, y: 0.23 * h),
            control2: CGPoint(x: 0.14 * w, y: 0.27 * h)
        )

        // Bridge of nose
        p.addCurve(
            to: CGPoint(x: 0.10 * w, y: 0.40 * h),
            control1: CGPoint(x: 0.15 * w, y: 0.34 * h),
            control2: CGPoint(x: 0.12 * w, y: 0.37 * h)
        )

        // Snout — long and tapered
        p.addCurve(
            to: CGPoint(x: 0.04 * w, y: 0.50 * h),
            control1: CGPoint(x: 0.08 * w, y: 0.44 * h),
            control2: CGPoint(x: 0.05 * w, y: 0.47 * h)
        )

        // Nostril bump
        p.addCurve(
            to: CGPoint(x: 0.06 * w, y: 0.54 * h),
            control1: CGPoint(x: 0.02 * w, y: 0.52 * h),
            control2: CGPoint(x: 0.03 * w, y: 0.54 * h)
        )

        // Lower jaw line — forward
        p.addCurve(
            to: CGPoint(x: 0.08 * w, y: 0.58 * h),
            control1: CGPoint(x: 0.06 * w, y: 0.56 * h),
            control2: CGPoint(x: 0.07 * w, y: 0.57 * h)
        )

        // Jaw teeth ridge
        p.addLine(to: CGPoint(x: 0.12 * w, y: 0.56 * h))
        p.addLine(to: CGPoint(x: 0.15 * w, y: 0.59 * h))
        p.addLine(to: CGPoint(x: 0.18 * w, y: 0.56 * h))
        p.addLine(to: CGPoint(x: 0.21 * w, y: 0.59 * h))

        // Lower jaw curve back
        p.addCurve(
            to: CGPoint(x: 0.35 * w, y: 0.62 * h),
            control1: CGPoint(x: 0.26 * w, y: 0.60 * h),
            control2: CGPoint(x: 0.30 * w, y: 0.62 * h)
        )

        // Throat/chin
        p.addCurve(
            to: CGPoint(x: 0.42 * w, y: 0.58 * h),
            control1: CGPoint(x: 0.38 * w, y: 0.62 * h),
            control2: CGPoint(x: 0.40 * w, y: 0.60 * h)
        )

        // --- Neck flowing into wing suggestion ---
        p.addCurve(
            to: CGPoint(x: 0.50 * w, y: 0.55 * h),
            control1: CGPoint(x: 0.44 * w, y: 0.56 * h),
            control2: CGPoint(x: 0.47 * w, y: 0.55 * h)
        )

        // Neck scales / ridges
        p.addCurve(
            to: CGPoint(x: 0.60 * w, y: 0.58 * h),
            control1: CGPoint(x: 0.54 * w, y: 0.56 * h),
            control2: CGPoint(x: 0.57 * w, y: 0.58 * h)
        )

        // Wing membrane start
        p.addCurve(
            to: CGPoint(x: 0.78 * w, y: 0.42 * h),
            control1: CGPoint(x: 0.65 * w, y: 0.55 * h),
            control2: CGPoint(x: 0.72 * w, y: 0.48 * h)
        )

        // Wing peak
        p.addCurve(
            to: CGPoint(x: 0.95 * w, y: 0.28 * h),
            control1: CGPoint(x: 0.84 * w, y: 0.36 * h),
            control2: CGPoint(x: 0.92 * w, y: 0.30 * h)
        )

        // Wing trailing edge scallop 1
        p.addCurve(
            to: CGPoint(x: 0.88 * w, y: 0.45 * h),
            control1: CGPoint(x: 0.96 * w, y: 0.34 * h),
            control2: CGPoint(x: 0.93 * w, y: 0.40 * h)
        )

        // Wing scallop 2
        p.addCurve(
            to: CGPoint(x: 0.92 * w, y: 0.52 * h),
            control1: CGPoint(x: 0.90 * w, y: 0.48 * h),
            control2: CGPoint(x: 0.92 * w, y: 0.50 * h)
        )

        // Wing scallop 3
        p.addCurve(
            to: CGPoint(x: 0.85 * w, y: 0.62 * h),
            control1: CGPoint(x: 0.93 * w, y: 0.56 * h),
            control2: CGPoint(x: 0.90 * w, y: 0.60 * h)
        )

        // Wing trailing edge down
        p.addCurve(
            to: CGPoint(x: 0.80 * w, y: 0.72 * h),
            control1: CGPoint(x: 0.83 * w, y: 0.66 * h),
            control2: CGPoint(x: 0.81 * w, y: 0.70 * h)
        )

        // Back body curve
        p.addCurve(
            to: CGPoint(x: 0.70 * w, y: 0.80 * h),
            control1: CGPoint(x: 0.78 * w, y: 0.76 * h),
            control2: CGPoint(x: 0.74 * w, y: 0.79 * h)
        )

        // Tail
        p.addCurve(
            to: CGPoint(x: 0.55 * w, y: 0.88 * h),
            control1: CGPoint(x: 0.65 * w, y: 0.82 * h),
            control2: CGPoint(x: 0.60 * w, y: 0.86 * h)
        )

        // Tail curl
        p.addCurve(
            to: CGPoint(x: 0.48 * w, y: 0.95 * h),
            control1: CGPoint(x: 0.50 * w, y: 0.90 * h),
            control2: CGPoint(x: 0.47 * w, y: 0.93 * h)
        )

        // Tail tip
        p.addCurve(
            to: CGPoint(x: 0.55 * w, y: 0.98 * h),
            control1: CGPoint(x: 0.49 * w, y: 0.97 * h),
            control2: CGPoint(x: 0.52 * w, y: 0.98 * h)
        )

        // Tail underside back up
        p.addCurve(
            to: CGPoint(x: 0.62 * w, y: 0.85 * h),
            control1: CGPoint(x: 0.58 * w, y: 0.96 * h),
            control2: CGPoint(x: 0.61 * w, y: 0.90 * h)
        )

        // Body underside
        p.addCurve(
            to: CGPoint(x: 0.72 * w, y: 0.72 * h),
            control1: CGPoint(x: 0.64 * w, y: 0.80 * h),
            control2: CGPoint(x: 0.68 * w, y: 0.75 * h)
        )

        // Back up to neck area
        p.addCurve(
            to: CGPoint(x: 0.68 * w, y: 0.50 * h),
            control1: CGPoint(x: 0.76 * w, y: 0.65 * h),
            control2: CGPoint(x: 0.74 * w, y: 0.56 * h)
        )

        // Neck back
        p.addCurve(
            to: CGPoint(x: 0.65 * w, y: 0.30 * h),
            control1: CGPoint(x: 0.66 * w, y: 0.42 * h),
            control2: CGPoint(x: 0.65 * w, y: 0.36 * h)
        )

        // Back spines
        p.addLine(to: CGPoint(x: 0.68 * w, y: 0.24 * h))
        p.addLine(to: CGPoint(x: 0.64 * w, y: 0.20 * h))
        p.addLine(to: CGPoint(x: 0.67 * w, y: 0.14 * h))

        // Close back to start
        p.addCurve(
            to: CGPoint(x: 0.62 * w, y: 0.08 * h),
            control1: CGPoint(x: 0.66 * w, y: 0.11 * h),
            control2: CGPoint(x: 0.64 * w, y: 0.09 * h)
        )

        p.closeSubpath()

        // --- Eye (negative space) ---
        let eyeCenter = CGPoint(x: 0.22 * w, y: 0.28 * h)
        let eyeRadius = 0.025 * w
        p.addEllipse(in: CGRect(
            x: eyeCenter.x - eyeRadius,
            y: eyeCenter.y - eyeRadius,
            width: eyeRadius * 2,
            height: eyeRadius * 2.4
        ))

        return p
    }
}

#Preview {
    VStack(spacing: 20) {
        DragonIcon(size: 96)
        DragonIcon(size: 64)
        DragonIcon(size: 32)
    }
    .padding()
    .background(.black)
}
