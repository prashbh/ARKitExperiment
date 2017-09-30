//
//  Plane.h
//  ARExample
//
//  Created by Prashant on 2017-09-28.
//  Copyright © 2017 Prashant Bhargava. All rights reserved.
//

#import <SceneKit/SceneKit.h>
#import <ARKit/ARKit.h>


@interface Plane : SCNNode
- (instancetype)initWithAnchor:(ARPlaneAnchor *)anchor;
- (void)update:(ARPlaneAnchor *)anchor;
- (void)setTextureScale;
@property (nonatomic,retain) ARPlaneAnchor *anchor;
@property (nonatomic, retain) SCNPlane *planeGeometry;
@end
