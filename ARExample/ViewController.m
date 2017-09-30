//
//  ViewController.m
//  ARExample
//
//  Created by Prashant on 2017-09-25.
//  Copyright © 2017 Prashant Bhargava. All rights reserved.
//

#import "ViewController.h"
#import "Plane.h"

@interface ViewController () <ARSCNViewDelegate> {
    NSMutableDictionary *planes;
}

@property (nonatomic, strong) IBOutlet ARSCNView *sceneView;

@property BOOL planeFound;
@property NSMutableArray *boxes;


@end

typedef NS_OPTIONS(NSUInteger, CollisionCategory) {
    CollisionCategoryBottom  = 1 << 0,
    CollisionCategoryCube    = 1 << 1,
};
    
@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    // Set the view's delegate
    self.sceneView.delegate = self;
    
    // Show statistics such as fps and timing information
    self.sceneView.showsStatistics = YES;
    
    // Create a new scene
    SCNScene *scene = [SCNScene new];
    planes = [NSMutableDictionary new];
    
    // Set the scene to the view
    self.sceneView.scene = scene;
    
    [self setupRecognizers];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    // Create a session configuration
    ARWorldTrackingConfiguration *configuration = [ARWorldTrackingConfiguration new];
    configuration.planeDetection = ARPlaneDetectionHorizontal;
    configuration.worldAlignment = ARWorldAlignmentGravityAndHeading;
    
    self.sceneView.debugOptions = ARSCNDebugOptionShowFeaturePoints;

    // Run the view's session
    [self.sceneView.session runWithConfiguration:configuration];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    // Pause the view's session
    [self.sceneView.session pause];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Release any cached data, images, etc that aren't in use.
}

- (void)setupRecognizers {
    // Single tap will insert a new piece of geometry into the scene
    UITapGestureRecognizer *tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTapFrom:)];
    tapGestureRecognizer.numberOfTapsRequired = 1;
    [self.sceneView addGestureRecognizer:tapGestureRecognizer];
    
    // Press and hold will cause an explosion causing geometry in the local vicinity of the explosion to move
    UILongPressGestureRecognizer *explosionGestureRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleHoldFrom:)];
    explosionGestureRecognizer.minimumPressDuration = 0.5;
    [self.sceneView addGestureRecognizer:explosionGestureRecognizer];
    
    UILongPressGestureRecognizer *hidePlanesGestureRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleHidePlaneFrom:)];
    hidePlanesGestureRecognizer.minimumPressDuration = 1;
    hidePlanesGestureRecognizer.numberOfTouchesRequired = 2;
    [self.sceneView addGestureRecognizer:hidePlanesGestureRecognizer];
}

- (void)handleTapFrom: (UITapGestureRecognizer *)recognizer {
    // Take the screen space tap coordinates and pass them to the
    // hitTest method on the ARSCNView instance
    CGPoint tapPoint = [recognizer locationInView:self.sceneView];
    NSArray<ARHitTestResult *> *result = [self.sceneView   hitTest:tapPoint types:ARHitTestResultTypeExistingPlaneUsingExtent];
    // If the intersection ray passes through any plane geometry they
    // will be returned, with the planes ordered by distance
    // from the camera
    if (result.count == 0) {
        return;
    }
    // If there are multiple hits, just pick the closest plane
    ARHitTestResult * hitResult = [result firstObject];
    [self insertGeometry:hitResult];
}

- (void)handleHoldFrom: (UILongPressGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateBegan) {
        return;
    }
    
    // Perform a hit test using the screen coordinates to see if the user pressed on
    // a plane.
    CGPoint holdPoint = [recognizer locationInView:self.sceneView];
    NSArray<ARHitTestResult *> *result = [self.sceneView hitTest:holdPoint types:ARHitTestResultTypeExistingPlaneUsingExtent];
    if (result.count == 0) {
        return;
    }
    
    ARHitTestResult * hitResult = [result firstObject];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self explode:hitResult];
    });
}

- (void)handleHidePlaneFrom: (UILongPressGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateBegan) {
        return;
    }
    
    // Hide all the planes
    for(NSUUID *planeId in planes) {
        [planes[planeId] hide];
    }
    
    // Stop detecting new planes or updating existing ones.
    ARWorldTrackingConfiguration *configuration = (ARWorldTrackingConfiguration *)self.sceneView.session.configuration;
    configuration.planeDetection = ARPlaneDetectionNone;
    [self.sceneView.session runWithConfiguration:configuration];
}

- (void)insertGeometry:(ARHitTestResult *)hitResult {
    float dimension = 0.1;
    SCNBox *cube = [SCNBox boxWithWidth:dimension
                                 height:dimension
                                 length:dimension
                          chamferRadius:0];
    SCNNode *node = [SCNNode nodeWithGeometry:cube];
    // The physicsBody tells SceneKit this geometry should be
    // manipulated by the physics engine
    node.physicsBody = [SCNPhysicsBody
                        bodyWithType:SCNPhysicsBodyTypeDynamic
                        shape:nil];
    node.physicsBody.mass = 2.0;
    node.physicsBody.categoryBitMask = CollisionCategoryCube;
    // We insert the geometry slightly above the point the user tapped
    // so that it drops onto the plane using the physics engine
    float insertionYOffset = 0.5;
    node.position = SCNVector3Make(
                                   hitResult.worldTransform.columns[3].x,
                                   hitResult.worldTransform.columns[3].y + insertionYOffset,
                                   hitResult.worldTransform.columns[3].z
                                   );
    // Add the cube to the scene
    [self.sceneView.scene.rootNode addChildNode:node];
    // Add the cube to an internal list for book-keeping
    [self.boxes addObject:node];
}

- (void)explode:(ARHitTestResult *)hitResult {
    // For an explosion, we take the world position of the explosion and the position of each piece of geometry
    // in the world. We then take the distance between those two points, the closer to the explosion point the
    // geometry is the stronger the force of the explosion.
    
    // The hitResult will be a point on the plane, we move the explosion down a little bit below the
    // plane so that the goemetry fly upwards off the plane
    float explosionYOffset = 0.1;
    
    SCNVector3 position = SCNVector3Make(
                                         hitResult.worldTransform.columns[3].x,
                                         hitResult.worldTransform.columns[3].y - explosionYOffset,
                                         hitResult.worldTransform.columns[3].z
                                         );
    
    // We need to find all of the geometry affected by the explosion, ideally we would have some
    // spatial data structure like an octree to efficiently find all geometry close to the explosion
    // but since we don't have many items, we can just loop through all of the current geoemtry
    for(SCNNode *cubeNode in self.boxes) {
        // The distance between the explosion and the geometry
        SCNVector3 distance = SCNVector3Make(
                                             cubeNode.worldPosition.x - position.x,
                                             cubeNode.worldPosition.y - position.y,
                                             cubeNode.worldPosition.z - position.z
                                             );
        
        float len = sqrtf(distance.x * distance.x + distance.y * distance.y + distance.z * distance.z);
        
        // Set the maximum distance that the explosion will be felt, anything further than 2 meters from
        // the explosion will not be affected by any forces
        float maxDistance = 2;
        float scale = MAX(0, (maxDistance - len));
        
        // Scale the force of the explosion
        scale = scale * scale * 2;
        
        // Scale the distance vector to the appropriate scale
        distance.x = distance.x / len * scale;
        distance.y = distance.y / len * scale;
        distance.z = distance.z / len * scale;
        
        // Apply a force to the geometry. We apply the force at one of the corners of the cube
        // to make it spin more, vs just at the center
        [cubeNode.physicsBody applyForce:distance atPosition:SCNVector3Make(0.05, 0.05, 0.05) impulse:YES];
    }
}

#pragma mark - ARSCNViewDelegate

// Override to create and configure nodes for anchors added to the view's session.
- (void)renderer:(id <SCNSceneRenderer>)renderer didAddNode:(SCNNode *)node forAnchor:(ARAnchor *)anchor {
    
    if (self.planeFound == NO)
    {
        if ([anchor isKindOfClass:[ARPlaneAnchor class]])
        {
            // Do something with the anchor and node
            Plane *plane = [[Plane alloc] initWithAnchor: (ARPlaneAnchor *)anchor];
            [planes setObject:plane forKey:anchor.identifier];

            [node addChildNode:plane];
        }
    }

}

- (void)renderer:(id <SCNSceneRenderer>)renderer
   didUpdateNode:(SCNNode *)node
       forAnchor:(ARAnchor *)anchor {
    // See if this is a plane we are currently rendering
    Plane *plane = [planes objectForKey:anchor.identifier];
    if (plane == nil) {
        return;
    }
    [plane update:(ARPlaneAnchor *)anchor];
}

- (void)renderer:(id <SCNSceneRenderer>)renderer didRemoveNode:(SCNNode *)node forAnchor:(ARAnchor *)anchor {
    // Nodes will be removed if planes multiple individual planes that are detected to all be
    // part of a larger plane are merged.
    [planes removeObjectForKey:anchor.identifier];
}

- (void)session:(ARSession *)session didFailWithError:(NSError *)error {
    // Present an error message to the user
    
}

- (void)sessionWasInterrupted:(ARSession *)session {
    // Inform the user that the session has been interrupted, for example, by presenting an overlay
    
}

- (void)sessionInterruptionEnded:(ARSession *)session {
    // Reset tracking and/or remove existing anchors if consistent tracking is required
    
}

@end
