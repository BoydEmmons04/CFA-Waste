import SwiftUI
import CoreMotion

struct ButtonView: View {
    let button: ButtonObject
    let selectedDate: Date // Pass selectedDate to display the correct tally
    let onTallyIncrement: (ButtonObject, Date) -> Void // Pass Date for proper tracking

    @State private var lastTapTime: Date = .distantPast // Debounce mechanism
    @State private var scale: CGFloat = 1.0 // New state for animation
    @StateObject private var tilt = DeviceTilt.shared

    var body: some View {
        ZStack {
            // Background: White Rounded Square
            RoundedRectangle(cornerRadius: 22.5)
                .fill(Color.white)
                .frame(width: 150, height: 150)
                .overlay(
                    ZStack {
                        // Background Image (artifact-resistant)
                        Image(button.image)
                            .resizable()
                            .renderingMode(.original)
                            .interpolation(.high)
                            .antialiased(true)
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 150, height: 150)
                            .opacity(0.38)

                        // Name and Price Calculation
                        VStack(spacing: 4) {
                            Spacer()
                            Text(button.name)
                                .font(.title3)
                                .bold()
                                .foregroundColor(.black)

                            // Display Price * Tally for the Selected Date
                            Text("$\(button.cost * Double(getTally(for: selectedDate)), specifier: "%.2f")")
                                .font(.headline)
                                .foregroundColor(.gray)
                        }
                        .padding(.bottom, 18)
                        .multilineTextAlignment(.center)

                        // Accent Strip (flat)
                        VStack {
                            Spacer()
                            Rectangle()
                                .fill(button.uiColor)
                                .frame(height: 9)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .compositingGroup()
                    .clipShape(RoundedRectangle(cornerRadius: 22.5))
                )
                // Soft inner glow that follows device tilt
                .overlay(
                    RoundedRectangle(cornerRadius: 22.5, style: .continuous)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: .white.opacity(0.22), location: 0.0),
                                    .init(color: .white.opacity(0.05), location: 0.6),
                                    .init(color: .white.opacity(0.0), location: 1.0)
                                ]),
                                startPoint: UnitPoint.from(angle: tilt.angle),
                                endPoint: UnitPoint.from(angle: tilt.angle + .pi)
                            ),
                            lineWidth: 6
                        )
                        .blur(radius: 3)
                        .mask(
                            RoundedRectangle(cornerRadius: 22.5, style: .continuous)
                                .stroke(lineWidth: 2.2)
                        )
                        .compositingGroup()
                        .allowsHitTesting(false)
                )
                // Rim shine (specular edge) that reacts to tilt
                .overlay(
                    RoundedRectangle(cornerRadius: 22.5, style: .continuous)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: .white.opacity(0.85), location: 0.0),
                                    .init(color: .white.opacity(0.10), location: 0.55),
                                    .init(color: .white.opacity(0.0),  location: 1.0)
                                ]),
                                startPoint: UnitPoint.from(angle: tilt.angle),
                                endPoint: UnitPoint.from(angle: tilt.angle + .pi)
                            ),
                            lineWidth: 1.2
                        )
                        .blendMode(.screen)
                        .compositingGroup()
                        .allowsHitTesting(false)
                )
                .shadow(radius: 3.75)

            // Notification Bubble (Tally for the Selected Date)
            if getTally(for: selectedDate) > 0 {
                ZStack {
                    Circle()
                        .fill(button.uiColor)
                        .frame(width: 37.5, height: 37.5)

                    Text("\(getTally(for: selectedDate))")
                        .font(.headline)
                        .foregroundColor(.white)
                        .bold()
                }
                .offset(x: 67.5, y: -67.5)
            }
        }
        .frame(width: 150, height: 150)
        .scaleEffect(scale) // Apply the scale effect for the animation
        .onTapGesture {
            handleTap()
        }
    }

    // MARK: - Handle Tap with Push Animation
    private func handleTap() {
        let now = Date()
        guard now.timeIntervalSince(lastTapTime) > 0.02 else { return } // Debounce taps within 20ms
        lastTapTime = now

        // Animate the button push: shrink the button then restore its scale.
        withAnimation(.easeIn(duration: 0.1)) {
            scale = 0.9
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeOut(duration: 0.1)) {
                scale = 1.0
            }
            // Increment tally for the selected date
            onTallyIncrement(button, selectedDate)
        }
    }

    // MARK: - Get Tally for a Specific Date
    private func getTally(for date: Date) -> Int {
        let formattedDate = formatDate(date)
        return button.tallies[formattedDate] ?? 0 // Retrieve tally for selected date
    }

    // MARK: - Date Formatting (UTC, stable across devices)
    private static let utcFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()

    private func formatDate(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = cal.startOfDay(for: date)
        return Self.utcFormatter.string(from: start)
    }
}

// MARK: - Motion → Lighting Direction
final class DeviceTilt: ObservableObject {
    static let shared = DeviceTilt()
    private let mgr = CMMotionManager()
    private let queue = OperationQueue()
    @Published var angle: CGFloat = .pi / 2 // default top lighting

    private init(updateHz: Double = 30) {
        guard mgr.isDeviceMotionAvailable else { return }
        mgr.deviceMotionUpdateInterval = 1.0 / updateHz
        mgr.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let m = motion else { return }
            // Map gravity to a portrait-friendly angle
            let x = m.gravity.x
            let y = -m.gravity.y
            let ang = atan2(y, x) // [-π, π]
            DispatchQueue.main.async {
                self?.angle = CGFloat(ang - .pi/2) // rotate so 0° ≈ top
            }
        }
    }

    deinit { mgr.stopDeviceMotionUpdates() }
}

// MARK: - Gradient endpoint from angle
fileprivate extension UnitPoint {
    static func from(angle: CGFloat) -> UnitPoint {
        let dx = cos(angle)
        let dy = sin(angle)
        return UnitPoint(x: 0.5 + 0.5 * dx, y: 0.5 - 0.5 * dy)
    }
}
