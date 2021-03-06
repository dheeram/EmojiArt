//
//  EmojiArtDocumentView.swift
//  EmojiArt
//  view
//
//  Created by Barry Martin on 6/12/20.
//  Copyright © 2020 Barry Martin. All rights reserved.
//

import SwiftUI

struct EmojiArtDocumentView: View {
    @ObservedObject var document: EmojiArtDocument
    
    var body: some View {
        VStack {
            ScrollView(.horizontal) {
                HStack {
                    ForEach(EmojiArtDocument.palette.map { String($0) }, id: \.self ) { emoji in
                        Text(emoji)
                            .font(Font.system(size: self.defaultEmojiSize))
                            .onDrag { NSItemProvider(object: emoji as NSString) }
                    }
                }
            }
            .padding(.horizontal)
            GeometryReader { geometry in
                ZStack {
                    Color.white.overlay(
                        OptionalImage(uiImage: self.document.backgroundImage)
                            .scaleEffect(self.zoomScale)
                            .offset(self.panOffset)
                    )
                        .gesture(
                            self.doubleTapToZoom(in: geometry.size)
                                .exclusively(before: self.singleTapToSelect(for: nil))
                    )
                    ForEach(self.document.emojis) { emoji in
                        Text(emoji.text)
                            //.font(self.font(for: emoji))
                            .font(animatableWithSize: emoji.fontSize * self.zoomScale(for: emoji))
                            .position(self.position(for: emoji, in: geometry.size))
                            .gesture(self.singleTapToSelect(for: emoji))
                            .gesture(self.longPress(for: emoji))
                            .gesture(self.dragSelectedEmoji(for: emoji))
                            .shadow(color: self.isEmojiSelected(emoji) ? .black : .clear , radius: 10 )
                        
                    }
                }
                .clipped()
                .gesture(self.panGesture())
                .gesture(self.zoomGesture())
                .edgesIgnoringSafeArea([.horizontal, .bottom])
                .onDrop(of: ["public.image","public.text"], isTargeted: nil) { providers, location in
                    // SwiftUI bug (as of 13.4)? the location is supposed to be in our coordinate system
                    // however, the y coordinate appears to be in the global coordinate system
                    //var location = geometry.convert(location, from: .global)
                    var location = CGPoint(x: location.x, y: geometry.convert(location, from: .global).y)
                    location = CGPoint(x: location.x - geometry.size.width/2, y: location.y - geometry.size.height/2)
                    location = CGPoint(x: location.x - self.panOffset.width, y: location.y - self.panOffset.height)
                    location = CGPoint(x: location.x / self.zoomScale, y: location.y / self.zoomScale)
                    return self.drop(providers: providers, at: location)
                }
            }
        }
    }
    
    @State private var selectedEmojis = Set<EmojiArt.Emoji>()
    
    private var isThereAnySelection: Bool {
        !selectedEmojis.isEmpty
    }
    
    private func singleTapToSelect(for emoji: EmojiArt.Emoji?) -> some Gesture {
        TapGesture(count: 1)
            .onEnded {
                if let emoji = emoji {
                    print("Tapped emoji id: \(emoji.id)")
                    self.selectedEmojis.toggleMatching(emoji)
                } else {
                    // single tap on background
                    // deselect all emojis
                    self.selectedEmojis.removeAll()
                }
        }
    }
    
    private func isEmojiSelected(_ emoji: EmojiArt.Emoji) -> Bool {
        selectedEmojis.contains(matching: emoji)
    }
    
    private func longPress(for emoji: EmojiArt.Emoji) -> some Gesture {
        LongPressGesture(minimumDuration: 2)
            .onEnded { _ in
                self.document.removeEmoji(emoji)
            }
    }
    
    @State private var steadyStateZoomScale: CGFloat = 1.0
    @GestureState private var gestureZoomScale: CGFloat = 1.0
    
    private var zoomScale: CGFloat {
        //steadyStateZoomScale * gestureZoomScale
        steadyStateZoomScale * (isThereAnySelection ? 1 : gestureZoomScale)
    }
    
    private func zoomScale(for emoji: EmojiArt.Emoji) -> CGFloat {
        if isEmojiSelected(emoji) {
            return steadyStateZoomScale * gestureZoomScale
        } else {
            return zoomScale
        }
    }
    
    private func doubleTapToZoom(in size: CGSize) -> some Gesture {
        TapGesture(count: 2)
            .onEnded {
                withAnimation {
                    self.zoomToFit(self.document.backgroundImage, in: size)
                }
        }
    }
    
    private func zoomToFit(_ image: UIImage?, in size: CGSize) {
        if let image = image, image.size.width > 0, image.size.height > 0 {
            let hZoom = size.width / image.size.width
            let vZoom = size.height / image.size.height
            self.steadyStatePanOffset = .zero
            self.steadyStateZoomScale = min(hZoom, vZoom)
        }
    }
    
    private func zoomGesture() -> some Gesture {
        MagnificationGesture()
            .updating($gestureZoomScale) { latestGestureScale, gestureZoomScale, transaction in
                gestureZoomScale = latestGestureScale
        }
        .onEnded { finalGestureScale in
            if self.isThereAnySelection {
                // zoom selected emojis
                self.selectedEmojis.forEach { emoji in
                    self.document.scaleEmoji(emoji, by: finalGestureScale)
                }
            } else {
                // zoom everything
                self.steadyStateZoomScale *= finalGestureScale
            }
        }
    }
    
    @GestureState private var gestureEmojiOffset: CGSize = .zero
    
    private func dragSelectedEmoji(for emoji: EmojiArt.Emoji) -> some Gesture {
        DragGesture()
            .updating($gestureEmojiOffset) { latestDragGestureValue, gestureEmojiOffset, transaction in
                gestureEmojiOffset = latestDragGestureValue.translation / self.zoomScale
        }
        .onEnded { finalDragGestureValue in
            let translation = finalDragGestureValue.translation / self.zoomScale
            self.document.moveEmoji(emoji, by: translation)
        }
    }
    
    @State private var steadyStatePanOffset: CGSize = .zero
    @GestureState private var gesturePanOffset: CGSize = .zero
    
    private var panOffset: CGSize {
        (steadyStatePanOffset + gesturePanOffset) * zoomScale
    }
    
    private func panGesture() -> some Gesture {
        DragGesture()
            .updating($gesturePanOffset) { latestDragGestureValue, gesturePanOffset, transaction in
                gesturePanOffset = latestDragGestureValue.translation / self.zoomScale
        }
        .onEnded { finalDragGestureValue in
            self.steadyStatePanOffset = self.steadyStatePanOffset + (finalDragGestureValue.translation / self.zoomScale)
        }
    }
    
    
    
    //    private func font(for emoji: EmojiArt.Emoji) -> Font {
    //        Font.system(size: emoji.fontSize * zoomScale)
    //    }
    
    private func position(for emoji: EmojiArt.Emoji, in size: CGSize) -> CGPoint {
        var location = emoji.location
        location = CGPoint(x: location.x * zoomScale, y: location.y * zoomScale)
        location = CGPoint(x: location.x + size.width/2, y: location.y + size.height/2)
        location = CGPoint(x: location.x + panOffset.width, y: location.y + panOffset.height)
        if isEmojiSelected(emoji) {
            location = CGPoint(x: location.x + gestureEmojiOffset.width,
                               y: location.y + gestureEmojiOffset.height)
        }
        return location
    }
    
    private func drop(providers: [NSItemProvider], at location: CGPoint) -> Bool {
        var found = providers.loadFirstObject(ofType: URL.self) { url in
            self.document.setBackgroundURL(url)
        }
        if !found {
            found = providers.loadObjects(ofType: String.self) { string in
                self.document.addEmoji(string, at: location, size: self.defaultEmojiSize)
            }
        }
        return found
    }
    
    private let defaultEmojiSize: CGFloat = 40
}







//struct ContentView_Previews: PreviewProvider {
//    static var previews: some View {
//        EmojiArtDocumentView()
//    }
//}
