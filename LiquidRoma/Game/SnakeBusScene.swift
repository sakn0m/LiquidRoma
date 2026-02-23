import SpriteKit
import GameplayKit

// MARK: - Game State

enum GameState {
    case playing
    case gameOver
}

// MARK: - Physics Categories

struct PhysicsCategory {
    static let none:  UInt32 = 0
    static let head:  UInt32 = 0x1
    static let food:  UInt32 = 0x2
    static let body:  UInt32 = 0x4
}

// MARK: - SnakeBusScene

/// A SpriteKit scene implementing a fluid, grid-less Snake game themed as a
/// Roman articulated bus ("lo snodato"). The bus head (motrice) moves along a
/// continuous direction vector; trailer segments follow the exact curved path
/// the head traced using a path-history buffer.
final class SnakeBusScene: SKScene {

    // MARK: - Constants

    /// Movement speed in points per second.
    private let busSpeed: CGFloat = 170

    /// Number of path-history frames between consecutive trailer segments.
    private let segmentSpacing: Int = 18

    /// Maximum number of trailer segments the bus can have.
    private let maxSegments: Int = 60

    /// Extra buffer frames kept beyond the strict requirement.
    private let historyBuffer: Int = 60

    /// Dimensions for the bus head.
    private let headWidth: CGFloat = 40
    private let headHeight: CGFloat = 20

    /// Dimensions for trailer segments (slightly smaller).
    private let trailerWidth: CGFloat = 36
    private let trailerHeight: CGFloat = 18

    /// How far from edges food can spawn and where the bus dies.
    private let wallPadding: CGFloat = 30

    /// Minimum distance from head centre to a body segment centre that
    /// triggers a self-collision.
    private let selfCollisionRadius: CGFloat = 12

    /// Time in seconds after game start before self-collision checks begin.
    private let selfCollisionGraceSeconds: TimeInterval = 2.0

    /// Roma bus red.
    private let busRed = UIColor(red: 0xC1 / 255.0,
                                  green: 0x27 / 255.0,
                                  blue: 0x2D / 255.0,
                                  alpha: 1)

    // MARK: - Nodes

    private var headNode: SKNode!
    private var trailerNodes: [SKNode] = []
    private var foodNode: SKNode?
    private var gridNode: SKNode?
    // Score label removed — SwiftUI HUD handles score display exclusively.
    // private var scoreLabel: SKLabelNode!
    // Game over overlay removed — SwiftUI handles it exclusively.

    // MARK: - State

    private(set) var gameState: GameState = .playing

    /// Current movement direction as a unit vector. Starts moving to the right.
    private var direction = CGVector(dx: 1, dy: 0)

    /// Queue for direction change requests so rapid swipes don't conflict.
    private var pendingDirection: CGVector?

    /// The path the head has traced. Index 0 is the most recent position.
    private var pathHistory: [CGPoint] = []

    /// Current number of trailer segments.
    private var segmentCount: Int = 0

    /// Running score.
    private(set) var score: Int = 0

    /// The timestamp of the previous frame (for delta-time calculation).
    private var lastUpdateTime: TimeInterval = 0

    /// Timestamp of the first update frame — used for time-based grace period.
    private var gameStartTime: TimeInterval = 0

    /// Total frames elapsed since game start — used for path history.
    private var frameCount: Int = 0

    /// Callback invoked whenever score or game state changes so the SwiftUI
    /// wrapper can react.
    var onScoreChanged: ((Int) -> Void)?
    var onGameOver: ((Int) -> Void)?

    // MARK: - Scene Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = UIColor(white: 0.14, alpha: 1)
        anchorPoint = CGPoint(x: 0, y: 0)

        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = self

        setupGrid()
        setupHead()
        spawnFood()
        installGestureRecognizers()

        // Seed the path history with the head's starting position so that
        // trailer segments don't jump.
        let startPos = CGPoint(x: size.width * 0.3, y: size.height * 0.5)
        for _ in 0..<(segmentSpacing * 3 + historyBuffer) {
            pathHistory.append(startPos)
        }
    }

    override func willMove(from view: SKView) {
        // Remove swipe gesture recognizers we installed so they don't leak.
        view.gestureRecognizers?.removeAll { $0 is UISwipeGestureRecognizer }
    }

    // MARK: - Background Grid

    private func setupGrid() {
        let grid = SKNode()
        let spacing: CGFloat = 40
        let lineColor = UIColor(white: 0.20, alpha: 1)

        // Vertical lines
        var x: CGFloat = 0
        while x <= size.width {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            let line = SKShapeNode(path: path)
            line.strokeColor = lineColor
            line.lineWidth = 0.5
            grid.addChild(line)
            x += spacing
        }

        // Horizontal lines
        var y: CGFloat = 0
        while y <= size.height {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            let line = SKShapeNode(path: path)
            line.strokeColor = lineColor
            line.lineWidth = 0.5
            grid.addChild(line)
            y += spacing
        }

        grid.zPosition = -10
        addChild(grid)
        gridNode = grid
    }

    // MARK: - Head Setup

    private func setupHead() {
        let container = SKNode()
        container.name = "head"
        container.position = CGPoint(x: size.width * 0.3, y: size.height * 0.5)
        container.zPosition = 10

        // Main body of the bus head
        let body = SKShapeNode(rectOf: CGSize(width: headWidth, height: headHeight),
                               cornerRadius: 5)
        body.fillColor = busRed
        body.strokeColor = UIColor(white: 0.15, alpha: 1)
        body.lineWidth = 1
        container.addChild(body)

        // Windshield detail (front of the bus — right side since we start facing right)
        let windshield = SKShapeNode(rectOf: CGSize(width: 8, height: headHeight - 6),
                                      cornerRadius: 2)
        windshield.fillColor = UIColor(red: 0.65, green: 0.80, blue: 0.95, alpha: 1)
        windshield.strokeColor = .clear
        windshield.position = CGPoint(x: headWidth / 2 - 6, y: 0)
        container.addChild(windshield)

        // Headlights
        for yOffset: CGFloat in [-headHeight / 2 + 3, headHeight / 2 - 3] {
            let light = SKShapeNode(circleOfRadius: 2)
            light.fillColor = .yellow
            light.strokeColor = .clear
            light.position = CGPoint(x: headWidth / 2 - 1, y: yOffset)
            container.addChild(light)
        }

        // Physics body for collision with food
        let physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: headWidth, height: headHeight))
        physicsBody.isDynamic = true
        physicsBody.affectedByGravity = false
        physicsBody.categoryBitMask = PhysicsCategory.head
        physicsBody.contactTestBitMask = PhysicsCategory.food
        physicsBody.collisionBitMask = PhysicsCategory.none
        container.physicsBody = physicsBody

        addChild(container)
        headNode = container
    }

    // Score label setup removed — SwiftUI HUD handles score display.

    // MARK: - Food Spawning

    private func spawnFood() {
        foodNode?.removeFromParent()

        let container = SKNode()
        container.name = "food"
        container.zPosition = 5

        // Yellow circle background
        let circle = SKShapeNode(circleOfRadius: 14)
        circle.fillColor = UIColor(red: 1, green: 0.82, blue: 0.1, alpha: 1)
        circle.strokeColor = UIColor(red: 0.85, green: 0.65, blue: 0, alpha: 1)
        circle.lineWidth = 2
        container.addChild(circle)

        // Passenger icon (simple person silhouette using shapes)
        let personHead = SKShapeNode(circleOfRadius: 3.5)
        personHead.fillColor = UIColor(white: 0.2, alpha: 1)
        personHead.strokeColor = .clear
        personHead.position = CGPoint(x: 0, y: 4)
        container.addChild(personHead)

        let personBody = SKShapeNode(rectOf: CGSize(width: 7, height: 8), cornerRadius: 2)
        personBody.fillColor = UIColor(white: 0.2, alpha: 1)
        personBody.strokeColor = .clear
        personBody.position = CGPoint(x: 0, y: -4)
        container.addChild(personBody)

        // Gentle pulse animation
        let pulse = SKAction.sequence([
            SKAction.scale(to: 1.12, duration: 0.5),
            SKAction.scale(to: 1.0, duration: 0.5)
        ])
        container.run(SKAction.repeatForever(pulse))

        // Random position with padding
        let padding = wallPadding + 20
        let x = CGFloat.random(in: padding...(size.width - padding))
        let y = CGFloat.random(in: padding...(size.height - padding))
        container.position = CGPoint(x: x, y: y)

        // Physics body
        let physicsBody = SKPhysicsBody(circleOfRadius: 14)
        physicsBody.isDynamic = false
        physicsBody.categoryBitMask = PhysicsCategory.food
        physicsBody.contactTestBitMask = PhysicsCategory.head
        physicsBody.collisionBitMask = PhysicsCategory.none
        container.physicsBody = physicsBody

        addChild(container)
        foodNode = container
    }

    // MARK: - Trailer Segment Creation

    private func makeTrailerNode(index: Int) -> SKNode {
        let container = SKNode()
        container.name = "trailer_\(index)"
        container.zPosition = CGFloat(9 - index)

        // Main body — slightly smaller than the head, progressively darker
        let darkenFactor = min(CGFloat(index) * 0.02, 0.2)
        let segColor = busRed.adjusted(brightnessBy: -darkenFactor)

        let body = SKShapeNode(rectOf: CGSize(width: trailerWidth, height: trailerHeight),
                               cornerRadius: 4)
        body.fillColor = segColor
        body.strokeColor = UIColor(white: 0.15, alpha: 1)
        body.lineWidth = 1
        container.addChild(body)

        // Window dots
        for xOff: CGFloat in [-8, 0, 8] {
            let window = SKShapeNode(rectOf: CGSize(width: 5, height: trailerHeight - 8),
                                      cornerRadius: 1.5)
            window.fillColor = UIColor(red: 0.55, green: 0.70, blue: 0.85, alpha: 0.7)
            window.strokeColor = .clear
            window.position = CGPoint(x: xOff, y: 0)
            container.addChild(window)
        }

        // Connector joint indicator (small dark circle at the back)
        let joint = SKShapeNode(circleOfRadius: 3)
        joint.fillColor = UIColor(white: 0.25, alpha: 1)
        joint.strokeColor = .clear
        joint.position = CGPoint(x: -trailerWidth / 2 - 2, y: 0)
        container.addChild(joint)

        return container
    }

    // MARK: - Gesture Recognizers

    private func installGestureRecognizers() {
        guard let view = self.view else { return }

        let directions: [UISwipeGestureRecognizer.Direction] = [.up, .down, .left, .right]
        for dir in directions {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
            swipe.direction = dir
            view.addGestureRecognizer(swipe)
        }
    }

    @objc private func handleSwipe(_ gesture: UISwipeGestureRecognizer) {
        guard gameState == .playing else { return }

        let newDirection: CGVector
        switch gesture.direction {
        case .up:    newDirection = CGVector(dx: 0, dy: 1)
        case .down:  newDirection = CGVector(dx: 0, dy: -1)
        case .left:  newDirection = CGVector(dx: -1, dy: 0)
        case .right: newDirection = CGVector(dx: 1, dy: 0)
        default: return
        }

        // Prevent 180-degree reversal (would cause instant self-collision).
        let dot = direction.dx * newDirection.dx + direction.dy * newDirection.dy
        if dot >= -0.01 {
            // Not a reversal — accept it.
            pendingDirection = newDirection
        }
    }

    // MARK: - Update Loop

    override func update(_ currentTime: TimeInterval) {
        guard gameState == .playing else { return }

        // Delta time calculation
        if lastUpdateTime == 0 {
            lastUpdateTime = currentTime
            gameStartTime = currentTime
        }
        let dt = min(currentTime - lastUpdateTime, 1.0 / 30.0) // cap to avoid huge jumps
        lastUpdateTime = currentTime
        frameCount += 1

        // Apply pending direction change
        if let pending = pendingDirection {
            direction = pending
            pendingDirection = nil
        }

        // Move head
        let dx = direction.dx * busSpeed * dt
        let dy = direction.dy * busSpeed * dt
        headNode.position.x += dx
        headNode.position.y += dy

        // Rotate head to face direction
        let angle = atan2(direction.dy, direction.dx)
        headNode.zRotation = angle

        // Push current position to front of path history
        pathHistory.insert(headNode.position, at: 0)

        // Trim path history to required length
        let requiredLength = segmentSpacing * (segmentCount + 1) + historyBuffer
        if pathHistory.count > requiredLength {
            pathHistory.removeLast(pathHistory.count - requiredLength)
        }

        // Update trailer positions
        updateTrailers()

        // Edge collision
        checkEdgeCollision()

        // Self-collision (only after time-based grace period)
        if (currentTime - gameStartTime) > selfCollisionGraceSeconds {
            checkSelfCollision()
        }
    }

    // MARK: - Trailer Updates

    private func updateTrailers() {
        for (i, node) in trailerNodes.enumerated() {
            let historyIndex = segmentSpacing * (i + 1)
            guard historyIndex < pathHistory.count else { continue }

            let targetPos = pathHistory[historyIndex]
            node.position = targetPos

            // Compute rotation from the segment's heading
            let lookAheadIndex = max(historyIndex - 3, 0)
            let aheadPos = pathHistory[lookAheadIndex]
            let dx = aheadPos.x - targetPos.x
            let dy = aheadPos.y - targetPos.y
            if dx != 0 || dy != 0 {
                node.zRotation = atan2(dy, dx)
            }
        }
    }

    // MARK: - Collision Checks

    private func checkEdgeCollision() {
        let pos = headNode.position
        let halfW = headWidth / 2
        let halfH = headHeight / 2

        if pos.x - halfW < 0 || pos.x + halfW > size.width ||
           pos.y - halfH < 0 || pos.y + halfH > size.height {
            triggerGameOver()
        }
    }

    private func checkSelfCollision() {
        guard segmentCount >= 3 else { return }

        let headPos = headNode.position

        // Only check segments that are far enough back to avoid false positives
        // with segments that are still close to the head after spawning.
        let startIndex = 3
        for i in startIndex..<trailerNodes.count {
            let segPos = trailerNodes[i].position
            let dx = headPos.x - segPos.x
            let dy = headPos.y - segPos.y
            let dist = sqrt(dx * dx + dy * dy)
            if dist < selfCollisionRadius {
                triggerGameOver()
                return
            }
        }
    }

    // MARK: - Physics Contact

    func didBegin(_ contact: SKPhysicsContact) {
        guard gameState == .playing else { return }

        let bodyA = contact.bodyA
        let bodyB = contact.bodyB

        let combined = bodyA.categoryBitMask | bodyB.categoryBitMask

        if combined == (PhysicsCategory.head | PhysicsCategory.food) {
            collectFood()
        }
    }

    // MARK: - Food Collection

    private func collectFood() {
        // Increment score
        score += 1
        onScoreChanged?(score)

        // Flash effect on the food location
        if let foodPos = foodNode?.position {
            let flash = SKShapeNode(circleOfRadius: 20)
            flash.fillColor = UIColor(red: 1, green: 0.9, blue: 0.3, alpha: 0.8)
            flash.strokeColor = .clear
            flash.position = foodPos
            flash.zPosition = 15
            addChild(flash)
            flash.run(SKAction.sequence([
                SKAction.group([
                    SKAction.scale(to: 2.5, duration: 0.3),
                    SKAction.fadeOut(withDuration: 0.3)
                ]),
                SKAction.removeFromParent()
            ]))
        }

        // Grow the bus
        growBus()

        // Spawn new food
        spawnFood()

        // Brief screen shake for juiciness
        let shakeAction = SKAction.sequence([
            SKAction.moveBy(x: 3, y: 3, duration: 0.03),
            SKAction.moveBy(x: -6, y: -3, duration: 0.03),
            SKAction.moveBy(x: 3, y: 0, duration: 0.03)
        ])
        gridNode?.run(shakeAction)
    }

    // MARK: - Growth

    private func growBus() {
        guard segmentCount < maxSegments else { return }

        let newTrailer = makeTrailerNode(index: segmentCount)

        // Place the new trailer at the position of the last segment or head
        if let last = trailerNodes.last {
            newTrailer.position = last.position
            newTrailer.zRotation = last.zRotation
        } else {
            // First trailer — place slightly behind head
            newTrailer.position = CGPoint(
                x: headNode.position.x - direction.dx * CGFloat(segmentSpacing),
                y: headNode.position.y - direction.dy * CGFloat(segmentSpacing)
            )
            newTrailer.zRotation = headNode.zRotation
        }

        addChild(newTrailer)
        trailerNodes.append(newTrailer)
        segmentCount += 1

        // Extend the path history to accommodate the new segment. We add
        // `segmentSpacing` copies of the current tail position so the new
        // segment has something to read immediately instead of glitching.
        let fillPos = pathHistory.last ?? headNode.position
        for _ in 0..<segmentSpacing {
            pathHistory.append(fillPos)
        }
    }

    // MARK: - Game Over

    private func triggerGameOver() {
        guard gameState == .playing else { return }
        gameState = .gameOver

        // Stop all movement
        isPaused = false // ensure we can still show UI

        // Notify SwiftUI
        onGameOver?(score)

        // Flash the head red
        let flash = SKAction.sequence([
            SKAction.colorize(with: .white, colorBlendFactor: 1.0, duration: 0.08),
            SKAction.colorize(with: busRed, colorBlendFactor: 0.0, duration: 0.08)
        ])
        headNode.children.first?.run(SKAction.repeat(flash, count: 5))

        // Show in-scene game over overlay
        showGameOverOverlay()
    }

    private func showGameOverOverlay() {
        // SpriteKit overlay removed — SwiftUI handles game over UI exclusively.
        // isPaused stays false so head-flash animation can still play.
    }

    // Touch-based restart removed — SwiftUI overlay handles restart.

    // MARK: - Restart

    func restartGame() {
        // Remove everything and start fresh
        removeAllChildren()
        removeAllActions()

        // Reset state
        trailerNodes.removeAll()
        pathHistory.removeAll()
        segmentCount = 0
        score = 0
        frameCount = 0
        lastUpdateTime = 0
        gameStartTime = 0
        direction = CGVector(dx: 1, dy: 0)
        pendingDirection = nil
        gameState = .playing
        foodNode = nil

        // Re-setup
        setupGrid()
        setupHead()
        spawnFood()

        // Re-seed path history
        let startPos = CGPoint(x: size.width * 0.3, y: size.height * 0.5)
        for _ in 0..<(segmentSpacing * 3 + historyBuffer) {
            pathHistory.append(startPos)
        }

        onScoreChanged?(0)
    }
}

// MARK: - SKPhysicsContactDelegate

extension SnakeBusScene: @preconcurrency SKPhysicsContactDelegate {}

// MARK: - UIColor Brightness Helper

private extension UIColor {
    /// Returns a new color with adjusted brightness. Negative values darken.
    func adjusted(brightnessBy factor: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return UIColor(hue: h, saturation: s,
                       brightness: max(0, min(1, b + factor)),
                       alpha: a)
    }
}
