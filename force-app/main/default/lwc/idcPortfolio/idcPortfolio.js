import { LightningElement,track } from 'lwc';
import res1Cover from '@salesforce/resourceUrl/residential1_cover';
import com1Cover from '@salesforce/resourceUrl/commercial1_cover';
import hos1Cover from '@salesforce/resourceUrl/hospitality1_cover';
import hea1Cover from '@salesforce/resourceUrl/healthcare1_cover';


// Import gallery images
import res1_1 from '@salesforce/resourceUrl/residential1_1';
import res1_2 from '@salesforce/resourceUrl/residential1_2';
import res1_3 from '@salesforce/resourceUrl/residential1_3';

import com1_1 from '@salesforce/resourceUrl/commercial1_1';
import com1_2 from '@salesforce/resourceUrl/commercial1_2';


import hos1_1 from '@salesforce/resourceUrl/hospitality1_1';
import hos1_2 from '@salesforce/resourceUrl/hospitality1_2';
import hos1_3 from '@salesforce/resourceUrl/hospitality1_3';

import hea1_1 from '@salesforce/resourceUrl/healthcare1_1';
import hea1_2 from '@salesforce/resourceUrl/healthcare1_2';




export default class IdcPortfolio extends LightningElement {
  categories = ['Residential', 'Commercial', 'Hospitality', 'Healthcare'];

  allProjects = [
    {
      id: 1,
      title: 'Urban Apartment',
      category: 'Residential',
      coverImage: res1Cover,
     images: [ res1_1,res1_2, res1_3]
    },
    {
      id: 2,
      title: 'Office Design',
      category: 'Commercial',
      coverImage: com1Cover,
       images: [com1_1,com1_2
       ]
    },
    {
      id: 3,
      title: 'Luxury Resort',
      category: 'Hospitality',
      coverImage: hos1Cover,
      images: [hos1_1,hos1_2,hos1_3]
    },
    {
      id: 4,
      title: 'Clinic Interiors',
      category: 'Healthcare',
      coverImage: hea1Cover,
      images: [ hea1_1,hea1_2]
    }
  ];

  @track filteredProjects = this.allProjects;
  @track selectedProjectImages = [];
  @track isModalOpen = false;

  filterCategory(event) {
    const selectedCategory = event.target.dataset.category;
    this.filteredProjects = this.allProjects.filter(proj => proj.category === selectedCategory);
  }

  showAll() {
    this.filteredProjects = this.allProjects;
  }

 openGallery(event) {
  const projectId = parseInt(event.currentTarget.dataset.id, 10);
  const project = this.allProjects.find(p => p.id === projectId);
  this.selectedProjectImages = project.images;
  this.isModalOpen = true;
}


  closeModal() {
    this.isModalOpen = false;
  }
}