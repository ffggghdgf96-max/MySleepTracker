//
//  SleepMasterPro.swift
//  SleepMaster Pro
//
//  Created by Blackbox AI
//

import SwiftUI
import AVFoundation
import CoreMotion
import HealthKit
import CoreData
import Charts
import WidgetKit

@main
struct SleepMasterProApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

class SleepTracker: ObservableObject {
    @Published var isTracking = false
    @Published var sleepDuration: TimeInterval = 0
    @Published var snoreCount = 0
    @Published var sleepScore = 0
    @Published var motionData: [Double] = []
    
    private var audioEngine = AVAudioEngine()
    private var motionManager = CMMotionManager()
    private var timer: Timer?
    
    func startTracking() {
        isTracking = true
        setupAudioDetection()
        setupMotionTracking()
        startTimer()
    }
    
    func stopTracking() {
        isTracking = false
        audioEngine.stop()
        motionManager.stopDeviceMotionUpdates()
        timer?.invalidate()
        calculateSleepScore()
    }
    
    private func setupAudioDetection() {
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(
            onBus: 0,
            bufferSize: 1024,
            format: recordingFormat
        ) { buffer, time in
            self.detectSnoring(buffer: buffer)
        }
        
        try? audioEngine.start()
    }
    
    private func detectSnoring(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        
        let sampleCount = Int(buffer.frameLength)
        let samples = stride(
            from: 0, 
            to: sampleCount, 
            by: 1
        ).map { Int64(channelData.pointee[$0]) }
        
        let rms = sqrt(
            Double(samples.reduce(0, +) / sampleCount)
        )
        
        if rms > 0.15 { // عتبة الشخير
            DispatchQueue.main.async {
                self.snoreCount += 1
            }
        }
    }
    
    private func setupMotionTracking() {
        motionManager.deviceMotionUpdateInterval = 0.1
        motionManager.startDeviceMotionUpdates(to: .main) { motion, error in
            if let acceleration = motion?.userAcceleration {
                let totalAcceleration = sqrt(
                    pow(acceleration.x, 2) +
                    pow(acceleration.y, 2) +
                    pow(acceleration.z, 2)
                )
                self.motionData.append(Double(totalAcceleration))
                
                if self.motionData.count > 1000 {
                    self.motionData.removeFirst(500)
                }
            }
        }
    }
    
    private func startTimer() {
        var startTime = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.sleepDuration = Date().timeIntervalSince(startTime)
        }
    }
    
    private func calculateSleepScore() {
        let durationScore = min(100, Int(sleepDuration / 3600 * 33.3))
        let snorePenalty = min(50, snoreCount * 2)
        let motionScore = motionAnalysisScore()
        
        sleepScore = max(0, durationScore + motionScore - snorePenalty)
    }
    
    private func motionAnalysisScore() -> Int {
        let avgMotion = motionData.reduce(0, +) / Double(motionData.count)
        return avgMotion < 0.05 ? 33 : 20
    }
}

// الواجهة الرئيسية
struct ContentView: View {
    @StateObject private var tracker = SleepTracker()
    @State private var showingStats = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                // حالة النوم الحالية
                SleepStatusCard(tracker: tracker)
                
                // أزرار التحكم
                VStack(spacing: 20) {
                    if tracker.isTracking {
                        Button("إيقاف التتبع") {
                            tracker.stopTracking()
                        }
                        .buttonStyle(StopButtonStyle())
                    } else {
                        Button("بدء تتبع النوم") {
                            tracker.startTracking()
                        }
                        .buttonStyle(StartButtonStyle())
                    }
                }
                
                // إحصائيات سريعة
                QuickStatsView(tracker: tracker)
                
                Spacer()
            }
            .padding()
            .navigationTitle("SleepMaster Pro")
            .sheet(isPresented: $showingStats) {
                SleepStatsView(tracker: tracker)
            }
        }
    }
}

struct SleepStatusCard: View {
    @ObservedObject var tracker: SleepTracker
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Image(systemName: "moon.stars")
                    .font(.system(size: 40))
                    .foregroundColor(.blue)
                VStack(alignment: .leading) {
                    Text(tracker.isTracking ? "جاري التتبع..." : "جاهز للنوم")
                        .font(.title2.bold())
                    if tracker.isTracking {
                        Text(timeString(from: tracker.sleepDuration))
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            if tracker.isTracking {
                HStack {
                    StatItem(title: "الشخير", value: tracker.snoreCount, icon: "wind")
                    StatItem(title: "الحركة", value: Int.random(in: 1...10), icon: "figure.walk")
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(20)
    }
    
    func timeString(from interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        return String(format: "%dس %dد", hours, minutes)
    }
}

struct QuickStatsView: View {
    @ObservedObject var tracker: SleepTracker
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("الإحصائيات السريعة")
                .font(.headline)
            
            HStack {
                StatCircle(value: tracker.sleepScore, label: "النتيجة")
                StatCircle(value: tracker.snoreCount, label: "شخير")
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(15)
        .shadow(radius: 5)
    }
}

struct SleepStatsView: View {
    @ObservedObject var tracker: SleepTracker
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // الرسم البياني
                    SleepChartView(data: tracker.motionData)
                    
                    // تفاصيل النوم
                    SleepDetailsView(tracker: tracker)
                    
                    // نصائح
                    SleepTipsView()
                }
                .padding()
            }
            .navigationTitle("تقرير النوم")
        }
    }
}

// إضافة Charts للرسوم البيانية
struct SleepChartView: View {
    let data: [Double]
    
    var body: some View {
        Chart {
            ForEach(Array(data.enumerated()), id: \.offset) { index, value in
                LineMark(
                    x: .value("الوقت", index),
                    y: .value("الحركة", value)
                )
            }
        }
        .frame(height: 200)
        .chartYAxis {
            AxisMarks(position: .leading)
        }
    }
}

// الأنماط
struct StartButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title2.bold())
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(
                LinearGradient(
                    colors: [.blue, .purple],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(30)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}

struct StopButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title2.bold())
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(Color.red)
            .cornerRadius(30)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}

struct StatCircle: View {
    let value: Int
    let label: String
    
    var body: some View {
        VStack {
            Text("\$value)")
                .font(.largeTitle.bold())
                .foregroundColor(.blue)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(width: 80, height: 80)
        .background(Color(.systemGray5))
        .clipShape(Circle())
    }
}