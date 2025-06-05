import SwiftUI
import AVFoundation
import AVKit
import Photos

// MARK: - Main App Structure
@main
struct DualPOVApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}

struct ContentView: View {
    @State private var selectedTab = 0
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var feedViewModel = FeedViewModel()
    @StateObject private var cameraRollManager = CameraRollManager()
    
    var body: some View {
        TabView(selection: $selectedTab) {
            FeedView(viewModel: feedViewModel)
                .tabItem {
                    Image(systemName: selectedTab == 0 ? "house.fill" : "house")
                    Text("Feed")
                }
                .tag(0)
            
            CameraView(
                cameraManager: cameraManager,
                cameraRollManager: cameraRollManager,
                selectedTab: $selectedTab
            )
            .tabItem {
                Image(systemName: selectedTab == 1 ? "camera.fill" : "camera")
                Text("Camera")
            }
            .tag(1)
            
            CameraRollView(manager: cameraRollManager)
                .tabItem {
                    Image(systemName: selectedTab == 2 ? "photo.on.rectangle" : "photo")
                    Text("Camera Roll")
                }
                .tag(2)
        }
        .accentColor(.purple)
        .task {
            await cameraManager.requestPermissions()
        }
    }
}

// MARK: - Models
struct VideoPost: Identifiable, Codable {
    let id = UUID()
    let title: String
    let creator: String
    let videoURL: String
    let thumbnailURL: String
    let views: Int
    let likes: Int
    let description: String
    let duration: Double
    
    static let mockData = [
        VideoPost(
            title: "back at it again",
            creator: "@naturelover",
            videoURL: "https://jelly-shareables.s3.amazonaws.com/87015E09-A11F-4E24-91D7-6D22A524656B/87015E09-A11F-4E24-91D7-6D22A524656B_original.mp4",
            thumbnailURL: "sunset",
            views: 125000,
            likes: 8420,
            description: "Captured this beautiful sunset from my rooftop. The colors were absolutely incredible! 🌅",
            duration: 15.0
        ),
        VideoPost(
            title: "annoucement",
            creator: "@artexplorer",
            videoURL: "https://jelly-shareables.s3.amazonaws.com/EAB4EB2B-0C53-46B3-87B0-6626A376EB82/EAB4EB2B-0C53-46B3-87B0-6626A376EB82_original.mp4",
            thumbnailURL: "street_art",
            views: 89000,
            likes: 5230,
            description: "Found this incredible mural in downtown. The detail is mind-blowing! 🎨",
            duration: 12.0
        ),
        VideoPost(
            title: "Reflecting on Performance: Seeking Improvement and Leniency",
            creator: "@coffeeguru",
            videoURL: "https://jelly-shareables.s3.amazonaws.com/D37FC389-8496-4C92-83A4-8B5936531CD3/D37FC389-8496-4C92-83A4-8B5936531CD3_original.mp4",
            thumbnailURL: "coffee",
            views: 45000,
            likes: 3100,
            description: "Perfect pour-over technique. The aroma alone is worth watching! ☕️",
            duration: 20.0
        )
    ]
}

struct DualPOVVideo: Identifiable, Codable {
    let id = UUID()
    let frontVideoURL: URL
    let backVideoURL: URL
    let combinedVideoURL: URL?
    let createdAt: Date
    let duration: Double
    let thumbnail: Data?
    
    static let mockVideo = DualPOVVideo(
        frontVideoURL: URL(string: "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4")!,
        backVideoURL: URL(string: "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4")!,
        combinedVideoURL: nil,
        createdAt: Date(),
        duration: 15.0,
        thumbnail: nil
    )
}

// MARK: - Complete CameraManager Class
@MainActor
class CameraManager: ObservableObject {
    @Published var hasPermission = false
    @Published var isRecording = false
    @Published var recordingTime: TimeInterval = 0
    @Published var recordingProgress: Double = 0
    @Published var isSimulator = false
    
    let frontCaptureSession = AVCaptureSession()
    let backCaptureSession = AVCaptureSession()
    
    private var recordingTimer: Timer?
    private var frontVideoOutput: AVCaptureMovieFileOutput?
    private var backVideoOutput: AVCaptureMovieFileOutput?
    private var frontOutputURL: URL?
    private var backOutputURL: URL?
    private let maxRecordingTime: TimeInterval = 15.0
    
    init() {
        checkEnvironment()
        Task {
            await checkPermissions()
        }
    }
    
    private func checkEnvironment() {
        #if targetEnvironment(simulator)
        isSimulator = true
        hasPermission = true
        #else
        isSimulator = false
        #endif
    }
    
    func requestPermissions() async {
        guard !isSimulator else {
            hasPermission = true
            return
        }
        
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        hasPermission = granted
        
        if granted {
            await setupCamera()
        }
    }
    
    private func checkPermissions() async {
        guard !isSimulator else {
            hasPermission = true
            return
        }
        
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            hasPermission = true
            await setupCamera()
        case .notDetermined:
            await requestPermissions()
        default:
            hasPermission = false
        }
    }
    
    func setupCamera() async {
        guard hasPermission && !isSimulator else { return }
        
        await setupCaptureSession(session: frontCaptureSession, position: .front)
        await setupCaptureSession(session: backCaptureSession, position: .back)
        
        Task {
            frontCaptureSession.startRunning()
            backCaptureSession.startRunning()
        }
    }
    
    private func setupCaptureSession(session: AVCaptureSession, position: AVCaptureDevice.Position) async {
        session.beginConfiguration()
        
        do {
            session.sessionPreset = .high
            
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
                session.commitConfiguration()
                return
            }
            
            let videoInput = try AVCaptureDeviceInput(device: camera)
            
            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
            }
            
            let videoOutput = AVCaptureMovieFileOutput()
            if session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
                
                if position == .front {
                    frontVideoOutput = videoOutput
                } else {
                    backVideoOutput = videoOutput
                }
            }
            
        } catch {
            print("Camera setup error: \(error)")
        }
        
        session.commitConfiguration()
    }
    
    func startRecording() {
        guard !isRecording else { return }
        
        isRecording = true
        recordingTime = 0
        recordingProgress = 0
        
        if isSimulator {
            startSimulatorRecording()
        } else {
            startRealRecording()
        }
    }
    
    private func startSimulatorRecording() {
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            Task { @MainActor in
                self.recordingTime += 0.1
                self.recordingProgress = self.recordingTime / self.maxRecordingTime
                
                if self.recordingTime >= self.maxRecordingTime {
                    Task {
                        _ = await self.stopRecording()
                    }
                }
            }
        }
    }
    
    private func startRealRecording() {
        frontOutputURL = createOutputURL(suffix: "front")
        backOutputURL = createOutputURL(suffix: "back")
        
        if let frontOutput = frontVideoOutput, let frontURL = frontOutputURL {
            frontOutput.startRecording(to: frontURL, recordingDelegate: RecordingDelegate())
        }
        
        if let backOutput = backVideoOutput, let backURL = backOutputURL {
            backOutput.startRecording(to: backURL, recordingDelegate: RecordingDelegate())
        }
        
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            Task { @MainActor in
                self.recordingTime += 0.1
                self.recordingProgress = self.recordingTime / self.maxRecordingTime
                
                if self.recordingTime >= self.maxRecordingTime {
                    Task {
                        _ = await self.stopRecording()
                    }
                }
            }
        }
    }
    
    func stopRecording() async -> DualPOVVideo? {
        guard isRecording else { return nil }
        
        isRecording = false
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        if isSimulator {
            return createMockVideo()
        } else {
            return await stopRealRecording()
        }
    }
    
    private func stopRealRecording() async -> DualPOVVideo? {
        frontVideoOutput?.stopRecording()
        backVideoOutput?.stopRecording()
        
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        guard let frontURL = frontOutputURL,
              let backURL = backOutputURL,
              FileManager.default.fileExists(atPath: frontURL.path),
              FileManager.default.fileExists(atPath: backURL.path) else {
            return createMockVideo()
        }
        
        let video = DualPOVVideo(
            frontVideoURL: frontURL,
            backVideoURL: backURL,
            combinedVideoURL: frontURL,
            createdAt: Date(),
            duration: recordingTime,
            thumbnail: await generateThumbnail(from: frontURL)
        )
        
        return video
    }
    
    private func createMockVideo() -> DualPOVVideo {
        return DualPOVVideo(
            frontVideoURL: URL(fileURLWithPath: "/tmp/mock_front.mp4"),
            backVideoURL: URL(fileURLWithPath: "/tmp/mock_back.mp4"),
            combinedVideoURL: nil,
            createdAt: Date(),
            duration: recordingTime,
            thumbnail: nil
        )
    }
    
    private func createOutputURL(suffix: String) -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileName = "dual_pov_\(suffix)_\(Date().timeIntervalSince1970).mp4"
        return documentsPath.appendingPathComponent(fileName)
    }
    
    private func generateThumbnail(from url: URL) async -> Data? {
        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        do {
            let cgImage = try await imageGenerator.image(at: CMTime.zero).image
            let uiImage = UIImage(cgImage: cgImage)
            return uiImage.jpegData(compressionQuality: 0.7)
        } catch {
            print("Thumbnail generation error: \(error)")
            return nil
        }
    }
}

// MARK: - Recording Delegate
private class RecordingDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            print("Recording error: \(error)")
        } else {
            print("Recording finished: \(outputFileURL)")
        }
    }
}

// MARK: - CameraRollManager Class
@MainActor
class CameraRollManager: ObservableObject {
    @Published var videos: [DualPOVVideo] = []
    @Published var isLoading = false
    
    private let userDefaults = UserDefaults.standard
    private let videosKey = "saved_dual_pov_videos"
    
    init() {
        loadVideos()
    }
    
    func addVideo(_ video: DualPOVVideo) {
        videos.insert(video, at: 0)
        saveVideos()
    }
    
    func deleteVideo(_ video: DualPOVVideo) {
        videos.removeAll { $0.id == video.id }
        deleteVideoFiles(video)
        saveVideos()
    }
    
    func deleteVideo(at indexSet: IndexSet) {
        for index in indexSet {
            let video = videos[index]
            deleteVideoFiles(video)
        }
        videos.remove(atOffsets: indexSet)
        saveVideos()
    }
    
    private func deleteVideoFiles(_ video: DualPOVVideo) {
        let fileManager = FileManager.default
        
        if fileManager.fileExists(atPath: video.frontVideoURL.path) {
            try? fileManager.removeItem(at: video.frontVideoURL)
        }
        
        if fileManager.fileExists(atPath: video.backVideoURL.path) {
            try? fileManager.removeItem(at: video.backVideoURL)
        }
        
        if let combinedURL = video.combinedVideoURL,
           combinedURL != video.frontVideoURL,
           combinedURL != video.backVideoURL,
           fileManager.fileExists(atPath: combinedURL.path) {
            try? fileManager.removeItem(at: combinedURL)
        }
    }
    
    func saveToPhotos(_ video: DualPOVVideo) async -> Bool {
        let authStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        
        let hasPermission: Bool
        if authStatus == .authorized {
            hasPermission = true
        } else {
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            hasPermission = (newStatus == .authorized)
        }
        
        guard hasPermission else {
            return false
        }
        
        let videoURL = video.combinedVideoURL ?? video.frontVideoURL
        
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            return false
        }
        
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
            }
            return true
        } catch {
            print("Error saving to photos: \(error)")
            return false
        }
    }
    
    private func loadVideos() {
        guard let data = userDefaults.data(forKey: videosKey) else {
            return
        }
        
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            videos = try decoder.decode([DualPOVVideo].self, from: data)
            cleanupInvalidVideos()
        } catch {
            print("Error loading videos: \(error)")
            videos = []
        }
    }
    
    private func saveVideos() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(videos)
            userDefaults.set(data, forKey: videosKey)
        } catch {
            print("Error saving videos: \(error)")
        }
    }
    
    private func cleanupInvalidVideos() {
        let validVideos = videos.filter { video in
            FileManager.default.fileExists(atPath: video.frontVideoURL.path) ||
            FileManager.default.fileExists(atPath: video.backVideoURL.path)
        }
        
        if validVideos.count != videos.count {
            videos = validVideos
            saveVideos()
        }
    }
    
    func getVideoFileSize(_ video: DualPOVVideo) -> String {
        let fileManager = FileManager.default
        var totalSize: Int64 = 0
        
        if let frontAttributes = try? fileManager.attributesOfItem(atPath: video.frontVideoURL.path) {
            totalSize += frontAttributes[.size] as? Int64 ?? 0
        }
        
        if let backAttributes = try? fileManager.attributesOfItem(atPath: video.backVideoURL.path) {
            totalSize += backAttributes[.size] as? Int64 ?? 0
        }
        
        if let combinedURL = video.combinedVideoURL,
           combinedURL != video.frontVideoURL,
           combinedURL != video.backVideoURL,
           let combinedAttributes = try? fileManager.attributesOfItem(atPath: combinedURL.path) {
            totalSize += combinedAttributes[.size] as? Int64 ?? 0
        }
        
        return ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
    
    func getTotalStorageUsed() -> String {
        let totalBytes = videos.reduce(0) { total, video in
            let fileManager = FileManager.default
            var videoSize: Int64 = 0
            
            if let frontAttributes = try? fileManager.attributesOfItem(atPath: video.frontVideoURL.path) {
                videoSize += frontAttributes[.size] as? Int64 ?? 0
            }
            
            if let backAttributes = try? fileManager.attributesOfItem(atPath: video.backVideoURL.path) {
                videoSize += backAttributes[.size] as? Int64 ?? 0
            }
            
            if let combinedURL = video.combinedVideoURL,
               combinedURL != video.frontVideoURL,
               combinedURL != video.backVideoURL,
               let combinedAttributes = try? fileManager.attributesOfItem(atPath: combinedURL.path) {
                videoSize += combinedAttributes[.size] as? Int64 ?? 0
            }
            
            return total + Int(videoSize)
        }
        
        return ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file)
    }
}

// MARK: - Feed View Model
@MainActor
class FeedViewModel: ObservableObject {
    @Published var posts: [VideoPost] = []
    @Published var isLoading = false
    
    func loadFeed() async {
        isLoading = true
        
        // Simulate network delay
        try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
        
        posts = VideoPost.mockData
        isLoading = false
    }
}

// MARK: - Feed View
struct FeedView: View {
    @ObservedObject var viewModel: FeedViewModel
    @State private var currentIndex = 0
    @State private var dragOffset: CGFloat = 0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                
                if viewModel.isLoading {
                    VStack {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.purple)
                        Text("Loading Feed...")
                            .foregroundColor(.white)
                            .padding(.top)
                    }
                } else {
                    TabView(selection: $currentIndex) {
                        ForEach(Array(viewModel.posts.enumerated()), id: \.element.id) { index, post in
                            VideoFeedCard(post: post, geometry: geometry)
                                .tag(index)
                        }
                    }
                    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                    .ignoresSafeArea()
                }
                
                // Top overlay with title
                VStack {
                    HStack {
                        Text("DualPOV")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Spacer()
                       
                        Button(action: {
                            Task {
                                await viewModel.loadFeed()
                            }
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(.white)
                                .font(.title2)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 10)
                    
                    Spacer()
                }
            }
        }
        .task {
            if viewModel.posts.isEmpty {
                await viewModel.loadFeed()
            }
        }
    }
}

struct VideoPlayerSubView: View {
    let videoURL: URL

    var body: some View {
        VideoPlayer(player: AVPlayer(url: videoURL))
            .aspectRatio(contentMode: .fit)
            .onAppear {
                // Autoplay
                AVPlayer(url: videoURL).play()
            }
            .ignoresSafeArea()
    }
}
struct VideoFeedCard: View {
    let post: VideoPost
    let geometry: GeometryProxy
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var isLiked = false
    @State private var showFullDescription = false
    @State private var showControls = false
    
    var body: some View {
        ZStack {
            // Video Player Background
            if let player = player {
                VideoPlayer(player: player)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .onTapGesture {
                        withAnimation {
                            if isPlaying {
                                player.pause()
                            } else {
                                player.play()
                            }
                            isPlaying.toggle()
                            showControls = true
                            
                            // Hide controls after 3 seconds
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                withAnimation {
                                    showControls = false
                                }
                            }
                        }
                    }
            } else {
                // Fallback gradient background while loading
                RoundedRectangle(cornerRadius: 0)
                    .fill(
                        LinearGradient(
                            colors: [.purple.opacity(0.3), .blue.opacity(0.3), .pink.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        VStack {
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(.white)
                            Text("Loading video...")
                                .foregroundColor(.white)
                                .padding(.top)
                        }
                    }
            }
            
            // Play/Pause overlay
            if showControls {
                VStack {
                    Spacer()
                    
                    HStack {
                        Spacer()
                        
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.white.opacity(0.8))
                            .background(Color.black.opacity(0.3))
                            .clipShape(Circle())
                        
                        Spacer()
                    }
                    
                    Spacer()
                }
                .transition(.opacity)
            }
            
            // Right side actions
            VStack {
                Spacer()
                
                HStack {
                    Spacer()
                    
                    VStack(spacing: 20) {
                        // Like button
                        VStack {
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                    isLiked.toggle()
                                }
                            }) {
                                Image(systemName: isLiked ? "heart.fill" : "heart")
                                    .font(.title2)
                                    .foregroundColor(isLiked ? .red : .white)
                                    .scaleEffect(isLiked ? 1.2 : 1.0)
                                    .shadow(color: .black.opacity(0.5), radius: 2)
                            }
                            
                            Text("\(post.likes + (isLiked ? 1 : 0))")
                                .font(.caption)
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.5), radius: 1)
                        }
                        
                        // Share button
                        VStack {
                            Button(action: {}) {
                                Image(systemName: "paperplane")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .shadow(color: .black.opacity(0.5), radius: 2)
                            }
                            
                            Text("Share")
                                .font(.caption)
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.5), radius: 1)
                        }
                        
                        // Views count
                        VStack {
                            Image(systemName: "eye")
                                .font(.title2)
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.5), radius: 2)
                            
                            Text(formatViews(post.views))
                                .font(.caption)
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.5), radius: 1)
                        }
                    }
                    .padding(.trailing, 20)
                }
                
                // Bottom info overlay
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(post.creator)
                            .font(.headline)
                            .foregroundColor(.white)
                            .fontWeight(.semibold)
                            .shadow(color: .black.opacity(0.7), radius: 1)
                        
                        Spacer()
                        
                        Text(formatDuration(post.duration))
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Capsule())
                    }
                    
                    Text(post.title)
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .fontWeight(.medium)
                        .shadow(color: .black.opacity(0.7), radius: 1)
                    
                    Text(showFullDescription ? post.description : String(post.description.prefix(100)) + (post.description.count > 100 ? "..." : ""))
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(showFullDescription ? nil : 2)
                        .shadow(color: .black.opacity(0.7), radius: 1)
                        .onTapGesture {
                            withAnimation {
                                showFullDescription.toggle()
                            }
                        }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
                .background(
                    LinearGradient(
                        colors: [Color.clear, Color.black.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            player?.pause()
        }
    }
    
    private func setupPlayer() {
        guard let url = URL(string: post.videoURL) else { return }
        
        let newPlayer = AVPlayer(url: url)
        self.player = newPlayer
        
        // Auto-play when video appears
        newPlayer.play()
        isPlaying = true
        
        // Loop the video
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: newPlayer.currentItem,
            queue: .main
        ) { _ in
            newPlayer.seek(to: .zero)
            newPlayer.play()
        }
        
        // Hide controls initially
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            withAnimation {
                showControls = false
            }
        }
    }
    
    private func formatViews(_ views: Int) -> String {
        if views >= 1_000_000 {
            return String(format: "%.1fM", Double(views) / 1_000_000)
        } else if views >= 1_000 {
            return String(format: "%.1fK", Double(views) / 1_000)
        } else {
            return "\(views)"
        }
    }
    
    private func formatDuration(_ duration: Double) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        if minutes > 0 {
            return String(format: "%d:%02d", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
    }
}

//struct VideoFeedCard: View {
//    let post: VideoPost
//    let geometry: GeometryProxy
//    @State private var isPlaying = false
//    @State private var isLiked = false
//    @State private var showFullDescription = false
//    
//    var body: some View {
//        ZStack {
//            // Video Player Background (Placeholder)
//            RoundedRectangle(cornerRadius: 0)
//                .fill(
//                    LinearGradient(
//                        colors: [.purple.opacity(0.3), .blue.opacity(0.3), .pink.opacity(0.3)],
//                        startPoint: .topLeading,
//                        endPoint: .bottomTrailing
//                    )
//                )
//                .overlay {
//                    Image(systemName: "play.circle.fill")
//                        .font(.system(size: 80))
//                        .foregroundColor(.white.opacity(0.8))
//                        .opacity(isPlaying ? 0 : 1)
//                        .animation(.easeInOut(duration: 0.3), value: isPlaying)
//                }
//                .onTapGesture {
//                    withAnimation {
//                        isPlaying.toggle()
//                    }
//                }
//            
//            // Right side actions
//            VStack {
//                Spacer()
//                
//                HStack {
//                    Spacer()
//                    
//                    VStack(spacing: 20) {
//                        // Like button
//                        VStack {
//                            Button(action: {
//                                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
//                                    isLiked.toggle()
//                                }
//                            }) {
//                                Image(systemName: isLiked ? "heart.fill" : "heart")
//                                    .font(.title2)
//                                    .foregroundColor(isLiked ? .red : .white)
//                                    .scaleEffect(isLiked ? 1.2 : 1.0)
//                            }
//                            
//                            Text("\(post.likes + (isLiked ? 1 : 0))")
//                                .font(.caption)
//                                .foregroundColor(.white)
//                        }
//                        
//                        // Share button
//                        VStack {
//                            Button(action: {}) {
//                                Image(systemName: "paperplane")
//                                    .font(.title2)
//                                    .foregroundColor(.white)
//                            }
//                            
//                            Text("Share")
//                                .font(.caption)
//                                .foregroundColor(.white)
//                        }
//                        
//                        // Views count
//                        VStack {
//                            Image(systemName: "eye")
//                                .font(.title2)
//                                .foregroundColor(.white)
//                            
//                            Text(formatViews(post.views))
//                                .font(.caption)
//                                .foregroundColor(.white)
//                        }
//                    }
//                    .padding(.trailing, 20)
//                }
//                
//                // Bottom info overlay
//                VStack(alignment: .leading, spacing: 8) {
//                    HStack {
//                        Text(post.creator)
//                            .font(.headline)
//                            .foregroundColor(.white)
//                            .fontWeight(.semibold)
//                        
//                        Spacer()
//                        
//                        Text(formatDuration(post.duration))
//                            .font(.caption)
//                            .foregroundColor(.white.opacity(0.8))
//                            .padding(.horizontal, 8)
//                            .padding(.vertical, 4)
//                            .background(Color.black.opacity(0.5))
//                            .clipShape(Capsule())
//                    }
//                    
//                    Text(post.title)
//                        .font(.subheadline)
//                        .foregroundColor(.white)
//                        .fontWeight(.medium)
//                    
//                    Text(showFullDescription ? post.description : String(post.description.prefix(100)) + (post.description.count > 100 ? "..." : ""))
//                        .font(.caption)
//                        .foregroundColor(.white.opacity(0.9))
//                        .lineLimit(showFullDescription ? nil : 2)
//                        .onTapGesture {
//                            withAnimation {
//                                showFullDescription.toggle()
//                            }
//                        }
//                }
//                .padding(.horizontal, 20)
//                .padding(.bottom, 30)
//            }
//        }
//        .frame(width: geometry.size.width, height: geometry.size.height)
//    }
//    
//    private func formatViews(_ views: Int) -> String {
//        if views >= 1_000_000 {
//            return String(format: "%.1fM", Double(views) / 1_000_000)
//        } else if views >= 1_000 {
//            return String(format: "%.1fK", Double(views) / 1_000)
//        } else {
//            return "\(views)"
//        }
//    }
//    
//    private func formatDuration(_ duration: Double) -> String {
//        let minutes = Int(duration) / 60
//        let seconds = Int(duration) % 60
//        if minutes > 0 {
//            return String(format: "%d:%02d", minutes, seconds)
//        } else {
//            return String(format: "%ds", seconds)
//        }
//    }
//}

// MARK: - Camera View
struct CameraView: View {
    @ObservedObject var cameraManager: CameraManager
    @ObservedObject var cameraRollManager: CameraRollManager
    @Binding var selectedTab: Int
    @State private var showPermissionAlert = false
    @State private var recordingStarted = false
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if !cameraManager.hasPermission {
                // Permission denied view
                VStack(spacing: 20) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    
                    Text("Camera Access Required")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text("DualPOV needs camera access to record dual perspective videos")
                        .font(.body)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    
                    Button(action: {
                        Task {
                            await cameraManager.requestPermissions()
                        }
                    }) {
                        Text("Enable Camera")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 30)
                            .padding(.vertical, 12)
                            .background(Color.purple)
                            .clipShape(Capsule())
                    }
                }
            } else {
                // Main camera interface
                VStack {
                    // Top bar
                    HStack {
                        Text("DualPOV Camera")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        if cameraManager.isSimulator {
                            Text("Simulator Mode")
                                .font(.caption)
                                .foregroundColor(.yellow)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.yellow.opacity(0.2))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 10)
                    
                    Spacer()
                    
                    // Dual camera preview
                    VStack(spacing: 16) {
                        // Front camera preview
                        DualCameraPreview(title: "Front Camera", isSimulator: cameraManager.isSimulator)
                        
                        // Back camera preview
                        DualCameraPreview(title: "Back Camera", isSimulator: cameraManager.isSimulator)
                    }
                    .padding(.horizontal, 20)
                    
                    Spacer()
                    
                    // Recording controls
                    VStack(spacing: 20) {
                        // Recording progress
                        if cameraManager.isRecording {
                            VStack(spacing: 8) {
                                Text(String(format: "%.1fs", cameraManager.recordingTime))
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                
                                ProgressView(value: cameraManager.recordingProgress)
                                    .progressViewStyle(LinearProgressViewStyle(tint: .red))
                                    .scaleEffect(y: 2)
                                    .padding(.horizontal, 40)
                            }
                        }
                        
                        // Record button
                        HStack(spacing: 40) {
                            // Cancel/Back button
                            Button(action: {
                                if cameraManager.isRecording {
                                    Task {
                                        _ = await cameraManager.stopRecording()
                                    }
                                } else {
                                    selectedTab = 0
                                }
                            }) {
                                Image(systemName: cameraManager.isRecording ? "xmark" : "chevron.left")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .frame(width: 50, height: 50)
                                    .background(Color.gray.opacity(0.3))
                                    .clipShape(Circle())
                            }
                            
                            // Main record button
                            Button(action: {
                                if cameraManager.isRecording {
                                    Task {
                                        if let video = await cameraManager.stopRecording() {
                                            cameraRollManager.addVideo(video)
                                            selectedTab = 2 // Go to Camera Roll
                                        }
                                    }
                                } else {
                                    cameraManager.startRecording()
                                    recordingStarted = true
                                }
                            }) {
                                ZStack {
                                    Circle()
                                        .stroke(Color.white, lineWidth: 4)
                                        .frame(width: 80, height: 80)
                                    
                                    Circle()
                                        .fill(cameraManager.isRecording ? Color.red : Color.white)
                                        .frame(width: cameraManager.isRecording ? 30 : 70, height: cameraManager.isRecording ? 30 : 70)
                                        .clipShape(RoundedRectangle(cornerRadius: cameraManager.isRecording ? 8 : 35))
                                }
                            }
                            .scaleEffect(cameraManager.isRecording ? 1.1 : 1.0)
                            .animation(.easeInOut(duration: 0.2), value: cameraManager.isRecording)
                            
                            // Camera roll button
                            Button(action: {
                                selectedTab = 2
                            }) {
                                Image(systemName: "photo.on.rectangle")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .frame(width: 50, height: 50)
                                    .background(Color.gray.opacity(0.3))
                                    .clipShape(Circle())
                            }
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .onAppear {
            if !cameraManager.hasPermission && !cameraManager.isSimulator {
                Task {
                    await cameraManager.requestPermissions()
                }
            }
        }
    }
}

struct DualCameraPreview: View {
    let title: String
    let isSimulator: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.white.opacity(0.8))
            
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.2))
                .overlay {
                    if isSimulator {
                        VStack {
                            Image(systemName: "camera")
                                .font(.system(size: 30))
                                .foregroundColor(.gray)
                            Text("Simulator Preview")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    } else {
                        // In a real app, this would contain AVCaptureVideoPreviewLayer
                        Text("Camera Preview")
                            .foregroundColor(.gray)
                    }
                }
                .frame(height: 160)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
        }
    }
}

// MARK: - Camera Roll View
struct CameraRollView: View {
    @ObservedObject var manager: CameraRollManager
    @State private var showingDeleteAlert = false
    @State private var videoToDelete: DualPOVVideo?
    @State private var selectedVideo: DualPOVVideo?
    @State private var showingVideoPlayer = false
    @State private var showingShareSheet = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if manager.videos.isEmpty {
                    // Empty state
                    VStack(spacing: 20) {
                        Image(systemName: "video.slash")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text("No Videos Yet")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Text("Start recording with the camera to see your dual POV videos here")
                            .font(.body)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        
                        Button(action: {
                            // This would typically switch to camera tab
                        }) {
                            Text("Go to Camera")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(.horizontal, 30)
                                .padding(.vertical, 12)
                                .background(Color.purple)
                                .clipShape(Capsule())
                        }
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8)
                        ], spacing: 16) {
                            ForEach(manager.videos) { video in
                                VideoThumbnailCard(
                                    video: video,
                                    onTap: {
                                        selectedVideo = video
                                        showingVideoPlayer = true
                                    },
                                    onDelete: {
                                        videoToDelete = video
                                        showingDeleteAlert = true
                                    },
                                    onShare: {
                                        selectedVideo = video
                                        showingShareSheet = true
                                    }
                                )
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 20)
                    }
                }
            }
            .navigationTitle("Camera Roll")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !manager.videos.isEmpty {
                        Menu {
                            Text("Storage: \(manager.getTotalStorageUsed())")
                            
                            Divider()
                            
                            Button(role: .destructive, action: {
                                showingDeleteAlert = true
                            }) {
                                Label("Clear All", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .foregroundColor(.white)
                        }
                    }
                }
            }
        }
        .alert("Delete Video", isPresented: $showingDeleteAlert, presenting: videoToDelete) { video in
            Button("Delete", role: .destructive) {
                manager.deleteVideo(video)
            }
            Button("Cancel", role: .cancel) {}
        } message: { video in
            Text("Are you sure you want to delete this video? This action cannot be undone.")
        }
        .sheet(isPresented: $showingVideoPlayer) {
            if let video = selectedVideo {
                VideoPlayerView(video: video)
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let video = selectedVideo {
                ShareSheet(items: [video.combinedVideoURL ?? video.frontVideoURL])
            }
        }
    }
}

struct VideoThumbnailCard: View {
    let video: DualPOVVideo
    let onTap: () -> Void
    let onDelete: () -> Void
    let onShare: () -> Void
    @State private var isSavingToPhotos = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail
            Button(action: onTap) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [.purple.opacity(0.4), .blue.opacity(0.4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        if let thumbnailData = video.thumbnail,
                           let uiImage = UIImage(data: thumbnailData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        } else {
                            VStack {
                                Image(systemName: "video")
                                    .font(.title)
                                    .foregroundColor(.white)
                                Text("DualPOV")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                        
                        // Play button overlay
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Image(systemName: "play.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .background(Color.black.opacity(0.5))
                                    .clipShape(Circle())
                                    .padding(8)
                            }
                        }
                        
                        // Duration badge
                        VStack {
                            HStack {
                                Spacer()
                                Text(formatDuration(video.duration))
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.black.opacity(0.7))
                                    .clipShape(Capsule())
                                    .padding(8)
                            }
                            Spacer()
                        }
                    }
                    .frame(height: 140)
            }
            
            // Video info and actions
            VStack(alignment: .leading, spacing: 4) {
                Text(formatDate(video.createdAt))
                    .font(.caption)
                    .foregroundColor(.white)
                    .fontWeight(.medium)
                
                Text("Duration: \(formatDuration(video.duration))")
                    .font(.caption2)
                    .foregroundColor(.gray)
                
                // Action buttons
                HStack(spacing: 12) {
                    Button(action: {
                        Task {
                            isSavingToPhotos = true
                            let success = await CameraRollManager().saveToPhotos(video)
                            isSavingToPhotos = false
                            // Could show success/failure feedback here
                        }
                    }) {
                        HStack(spacing: 4) {
                            if isSavingToPhotos {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "square.and.arrow.down")
                                    .font(.caption)
                            }
                        }
                        .foregroundColor(.blue)
                    }
                    .disabled(isSavingToPhotos)
                    
                    Button(action: onShare) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    
                    Spacer()
                }
            }
        }
        .padding(12)
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private func formatDuration(_ duration: Double) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        if minutes > 0 {
            return String(format: "%d:%02d", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct VideoPlayerView: View {
    let video: DualPOVVideo
    @Environment(\.dismiss) private var dismiss
    @State private var showingFrontCamera = true
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack {
                    // Video player area
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.2))
                        .overlay {
                            VStack {
                                Image(systemName: "play.rectangle")
                                    .font(.system(size: 60))
                                    .foregroundColor(.gray)
                                Text(showingFrontCamera ? "Front Camera" : "Back Camera")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                Text("Tap to play video")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                        .frame(maxHeight: 400)
                        .padding()
                    
                    // Camera switch toggle
                    HStack {
                        Text("View:")
                            .foregroundColor(.white)
                        
                        Picker("Camera View", selection: $showingFrontCamera) {
                            Text("Front").tag(true)
                            Text("Back").tag(false)
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .frame(width: 150)
                    }
                    .padding(.horizontal)
                    
                    Spacer()
                    
                    // Video details
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Video Details")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        HStack {
                            Text("Duration:")
                                .foregroundColor(.gray)
                            Text(String(format: "%.1f seconds", video.duration))
                                .foregroundColor(.white)
                            Spacer()
                        }
                        
                        HStack {
                            Text("Created:")
                                .foregroundColor(.gray)
                            Text(formatDate(video.createdAt))
                                .foregroundColor(.white)
                            Spacer()
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                    
                    Spacer()
                }
            }
            .navigationTitle("Video Player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Share Sheet Helper
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

