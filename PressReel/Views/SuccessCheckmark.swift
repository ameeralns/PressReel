import SwiftUI

struct SuccessCheckmark: View {
    @State private var trimEnd: CGFloat = 0
    @State private var scale: CGFloat = 0
    @State private var opacity: Double = 0
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.red.opacity(0.3), lineWidth: 4)
                .frame(width: 100, height: 100)
                .scaleEffect(scale)
            
            Circle()
                .trim(from: 0, to: trimEnd)
                .stroke(Color.red, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 100, height: 100)
                .rotationEffect(.degrees(-90))
                .scaleEffect(scale)
            
            Path { path in
                path.move(to: CGPoint(x: 30, y: 50))
                path.addLine(to: CGPoint(x: 45, y: 65))
                path.addLine(to: CGPoint(x: 70, y: 35))
            }
            .trim(from: 0, to: trimEnd)
            .stroke(Color.red, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            .frame(width: 100, height: 100)
            .scaleEffect(scale)
            .opacity(opacity)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5)) {
                scale = 1
            }
            withAnimation(.easeInOut(duration: 1).delay(0.5)) {
                trimEnd = 1
                opacity = 1
            }
        }
    }
} 