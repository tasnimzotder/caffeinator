import SwiftUI

struct AnimatedCoffeeIcon: View {
    let isActive: Bool
    @State private var steamPhase: CGFloat = 0
    
    var body: some View {
        ZStack {
            // Cup base
            Image(systemName: isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                .font(.title2)
                .foregroundStyle(isActive ? .brown : .secondary)
                .symbolEffect(.bounce, value: isActive)
            
            // Steam animation when active
            if isActive {
                SteamView()
                    .offset(y: -12)
            }
        }
        .animation(AppAnimation.spring, value: isActive)
    }
}

struct SteamView: View {
    var body: some View {
        HStack(spacing: 2) {
            SteamParticle(delay: 0)
            SteamParticle(delay: 0.25)
            SteamParticle(delay: 0.5)
        }
    }
}

struct SteamParticle: View {
    let delay: Double
    
    @State private var offset: CGFloat = 0
    @State private var opacity: Double = 0.5
    @State private var scale: CGFloat = 1.0
    @State private var xOffset: CGFloat = 0
    
    var body: some View {
        Circle()
            .fill(.secondary.opacity(opacity))
            .frame(width: 3, height: 3)
            .scaleEffect(scale)
            .offset(x: xOffset, y: offset)
            .onAppear {
                startAnimation()
            }
    }
    
    private func startAnimation() {
        // Random horizontal drift
        let randomDrift = CGFloat.random(in: -2...2)
        
        withAnimation(
            .easeOut(duration: 1.0)
            .repeatForever(autoreverses: false)
            .delay(delay)
        ) {
            offset = -8
            opacity = 0
            scale = 1.3
            xOffset = randomDrift
        }
    }
}
