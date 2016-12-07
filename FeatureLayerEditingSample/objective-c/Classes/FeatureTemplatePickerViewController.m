// Copyright 2012 ESRI
//
// All rights reserved under the copyright laws of the United States
// and applicable international laws, treaties, and conventions.
//
// You may freely redistribute and use this sample code, with or
// without modification, provided you include the original copyright
// notice and use restrictions.
//
// See the use restrictions at http://help.arcgis.com/en/sdk/10.0/usageRestrictions.htm
//

#import "FeatureTemplatePickerViewController.h"

@implementation FeatureTemplatePickerViewController
@synthesize featureTemplatesTableView = _featureTemplatesTableView;
@synthesize delegate = _delegate;
@synthesize infos = _infos;


// in iOS7 this gets called and hides the status bar so the view does not go under the top iPhone status bar
- (BOOL)prefersStatusBarHidden
{
    return YES;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    
}

- (void) addTemplatesFromLayer:(AGSFeatureLayer*)layer {

    //Instantiate the array to hold all templates from this layer
    if(!self.infos)
        self.infos = [[NSMutableArray alloc] init];
    
    if ([((AGSFeatureLayer *)layer).featureTable isKindOfClass:[AGSArcGISFeatureTable class]]) {
        AGSArcGISFeatureTable *fTable = (AGSArcGISFeatureTable *)((AGSFeatureLayer *)layer).featureTable;
        AGSArcGISFeatureLayerInfo *layerInfo = fTable.layerInfo;

        //If layer contains only templates (no feature types)
        //For each template
        if (layerInfo.featureTemplates!=nil && [layerInfo.featureTemplates count]>0) {
            for (AGSFeatureTemplate* template in layerInfo.featureTemplates) {
                
                FeatureTemplatePickerInfo* info =
                [[FeatureTemplatePickerInfo alloc] init];
                info.featureLayer = layer;
                info.featureTemplate = template;
                info.featureType = nil;
                info.featureTable = fTable;
                
                //Add to array
                [self.infos addObject:info];
            }
            //Otherwise, if layer contains feature types
        }else{
            //For each type
            for (AGSFeatureType* type in layerInfo.featureTypes) {
                //For each template in type
                for (AGSFeatureTemplate* template in type.templates) {
                    
                    FeatureTemplatePickerInfo* info =
                    [[FeatureTemplatePickerInfo alloc] init];
                    info.featureLayer = layer;
                    info.featureTemplate = template;
                    info.featureType = type;
                    info.featureTable = fTable;
                    
                    //Add to  array
                    [self.infos addObject:info];
                    
                }
            }
        }
    }
    
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    return YES;
}

- (IBAction) dismiss {
    //Notify the delegate that user tried to dismiss the view controller
	if ([self.delegate respondsToSelector:@selector(featureTemplatePickerViewControllerWasDismissed:)]){
		[self.delegate featureTemplatePickerViewControllerWasDismissed:self];
	}
}

#pragma mark -
#pragma mark UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @"Templates";
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self.infos count];
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    
    //Get a cell
	static NSString *CellIdentifier = @"Cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier];
		cell.selectionStyle = UITableViewCellSelectionStyleBlue;
    }

    
    //Set its label, image, etc for the template
    FeatureTemplatePickerInfo* info = [self.infos objectAtIndex:indexPath.row];
	cell.textLabel.font = [UIFont systemFontOfSize:12.0];
	cell.textLabel.text = info.featureTemplate.name;
    if (info.swatch) {
        cell.imageView.image = info.swatch;
    } else {
        //create dummy feature and symbol to get the swatch from
        AGSFeature *feature = [info.featureTable createFeatureWithTemplate:info.featureTemplate];
        AGSSymbol *symbol = [info.renderer symbolForFeature:feature];
        [symbol createSwatchWithCompletion:^(UIImage *swatch, NSError *error) {
            info.swatch = swatch;
            [tableView reloadData];
        }];
    }

    return cell;
}

#pragma mark -
#pragma mark UITableViewDelegate
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    
    //Notify the delegate that the user picked a feature template
    if ([self.delegate respondsToSelector:@selector(featureTemplatePickerViewController:didSelectFeatureTemplate:forTable:)]){
              
        FeatureTemplatePickerInfo* info = [self.infos objectAtIndex:indexPath.row];
        [self.delegate featureTemplatePickerViewController:self didSelectFeatureTemplate:info.featureTemplate forTable:info.featureTable];
    }    
    
    //Unselect the cell
    [tableView cellForRowAtIndexPath:indexPath].selected = NO;
    
    
}

#pragma mark - 

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

- (void)viewDidUnload {
    [super viewDidUnload];
	self.featureTemplatesTableView = nil;
    self.delegate = nil;
    
}


@end

@implementation FeatureTemplatePickerInfo

@synthesize featureType = _featureType;
@synthesize featureTemplate = _featureTemplate;
@synthesize featureLayer = _featureLayer;

@end