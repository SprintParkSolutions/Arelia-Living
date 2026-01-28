import { LightningElement } from 'lwc';
import residentialIcon from '@salesforce/resourceUrl/residential';
import commercialIcon from '@salesforce/resourceUrl/commercial';
import renovationIcon from '@salesforce/resourceUrl/renovation';
import consultingIcon from '@salesforce/resourceUrl/consulting';
export default class IdcOurServices extends LightningElement {
    residentialIcon = residentialIcon;
    commercialIcon = commercialIcon;
    renovationIcon = renovationIcon;
     consultingIcon = consultingIcon;
}